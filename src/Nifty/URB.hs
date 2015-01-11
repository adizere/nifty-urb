module Nifty.URB where


import Nifty.PointToPointLink
import Nifty.BEB
import Nifty.Message
import Nifty.DeliveryGuard

import Text.Printf
import System.Random
import System.IO
import Control.Concurrent.STM.TChan
import Control.Concurrent.BoundedChan
import Control.Concurrent                   (threadDelay)
import Control.Concurrent.MVar              (takeMVar, MVar)
import Control.Concurrent                   (forkIO)
import Control.Monad.STM                    (atomically)
import Network.Socket                       hiding (recv)
import Data.Maybe
import qualified Data.ByteString        as L
import qualified Data.ByteString.Char8  as C
import qualified Data.Map.Strict        as M
import qualified Data.HashTable.IO      as H


-- type alias
type HashTable k v = H.CuckooHashTable k v

egressChanLength :: Int
egressChanLength = 10


iMsgCollectorLimit :: Int
iMsgCollectorLimit = 100

getOutputFile :: Int -> String
getOutputFile pId =
    "da_proc_" ++ (show pId) ++ ".out"


startURB :: (Int, [(String, Int)], Int) -> MVar (Int) -> IO ()
startURB (procId, ipsPorts, msgCnt) stMVar = do
    handle <- openFile (getOutputFile procId) WriteMode
    eChan <- setupNetwork procId ipsPorts handle
    takeMVar stMVar >> startURBroadcast eChan procId msgCnt 1 handle


startURBroadcast ::
    BoundedChan (L.ByteString)
    -> Int
    -> Int
    -> Int
    -> Handle
    -> IO ()
startURBroadcast _ _ 0 _ _ = return ()
-- broadcasts indefinitely
startURBroadcast eChan procId (-1) seqNr handle = do
    lim <- fetchMsgLimit 300
    let nSeqNr = seqNr + lim
    let nSeqNrByteSt = C.pack (show seqNr ++ "-" ++ show nSeqNr)
    mapM_ (\s-> hPrintf handle "b %d\n" s) [seqNr..nSeqNr]
    writeChan eChan $ serializeOriginMessageContentB nSeqNrByteSt procId
    threadDelay 10000
    startURBroadcast eChan procId (-1) (nSeqNr + 1) handle
-- broadcasts until the msgCnt limit is reached
startURBroadcast eChan procId msgCnt seqNr handle = do
    lim <- fetchMsgLimit msgCnt
    let nSeqNr = seqNr + lim - 1
    let nSeqNrByteSt = C.pack (show seqNr ++ "-" ++ show (nSeqNr))
    mapM_ (\s-> hPrintf handle "b %d\n" s) [seqNr..nSeqNr]
    writeChan eChan $ serializeOriginMessageContentB nSeqNrByteSt procId
    threadDelay 10000
    startURBroadcast eChan procId (msgCnt - lim) (nSeqNr + 1) handle


fetchMsgLimit :: Int -> IO Int
fetchMsgLimit l =
    if l <= 10
        then return l
        else if l > 300
                then getStdRandom (randomR (9,300))
                else getStdRandom (randomR (9,l))


setupNetwork ::
    Int
    -> [(String, Int)]
    -> Handle
    -> IO (BoundedChan L.ByteString)
setupNetwork pId ipsPorts handle =
    establishPTPLinks pAddr foreignAddresses
        >>= setupMessageCollector (head $ show pId) handle
    where
        foreignAddresses = [ ipsPorts!!fId | fId <- [0..4], fId /= (pId-1) ]
        pAddr = ipsPorts!!(pId-1)


setupMessageCollector ::
    Char
    -> Handle
    -> (TChan L.ByteString, [Socket])
    -> IO (BoundedChan L.ByteString)
setupMessageCollector pId handle (iChan, eSockets) = do
    eChan <- newBoundedChan egressChanLength :: IO (BoundedChan L.ByteString)
    fw <- H.new :: IO (HashTable L.ByteString L.ByteString)
    dlv <- H.new :: IO (HashTable Char DeliveryGuard)
    mapM_ (\key -> H.insert dlv key value) ['1'..'5']
    _ <- forkIO (messageCollector handle pId eChan eSockets iChan M.empty fw dlv)
    return eChan
    where
        value = newDeliveryGuard


collectAvailableIMsg :: TChan (L.ByteString)    -- input channel
                        -> [L.ByteString]       -- accumulator
                        -> Int                  -- limit
                        -> IO ([L.ByteString])
collectAvailableIMsg _     acc 0        = return acc
collectAvailableIMsg iChan acc limit    = do
    maybeIMsg <- atomically $ tryReadTChan iChan
    case maybeIMsg of
        Just iMsg   -> collectAvailableIMsg iChan (iMsg:acc) (limit-1)
        Nothing     -> return acc


collectAvailableEMsg :: BoundedChan (L.ByteString)
                        -> [L.ByteString]
                        -> Int
                        -> IO ([L.ByteString])
collectAvailableEMsg _     acc 0        = return acc
collectAvailableEMsg eChan acc limit    = do
    maybeEMsg <- tryReadChan eChan
    case maybeEMsg of
        Just eMsg   -> collectAvailableEMsg eChan (eMsg:acc) (limit-1)
        Nothing     -> return acc


deliverURB :: L.ByteString -> IO ()
deliverURB msg = putStrLn $ "deliveree: " ++ (show $ L.take 3 msg)


messageCollector ::
    Handle
    -> Char                                    -- process ID
    -> BoundedChan (L.ByteString)           -- egress channel
    -> [Socket]                             -- egress sockets
    -> TChan (L.ByteString)                 -- ingress channel
    -> M.Map (L.ByteString) L.ByteString    -- histories
    -> HashTable L.ByteString L.ByteString  -- forward
    -> HashTable Char DeliveryGuard         -- delivered
    -> IO ()
messageCollector handle pId eChan eSockets iChan histories fw dlv = do
    allIMsg <- collectAvailableIMsg iChan [] iMsgCollectorLimit
    -- putStrLn $ "Fetched some ingress messages: " ++ (show allIMsg)
    let (nHistories, readyForDelivery, addToFw) =
            updateHistories pId histories allIMsg [] []
    handleDelivery handle readyForDelivery dlv
    allEMsg <- collectAvailableEMsg eChan [] 1
    -- putStrLn $ "Collected some egress messages: " ++ (show allEMsg)
    let nnHistories = addEMsgsToHistories allEMsg nHistories
    updateForward allEMsg addToFw fw
    handleBroadcast fw pId eSockets
    threadDelay 10000
    -- let nnnHistories = compactHistories readyToDelete nnHistories
    -- if pId == '1'
    --     then do
    --         b <- H.foldM getLength 0 fw
    --         putStrLn $ "lengths " ++ show (length addToFw) ++ " " ++
    --                     show (M.size nnHistories) ++ " " ++
    --                     show (length addToFw) ++ " " ++
    --                     show (length readyToDelete) ++ " " ++ (show b)

    --         messageCollector pId eChan eSockets iChan nnHistories fw dlv
    --     else
    messageCollector handle pId eChan eSockets iChan nnHistories fw dlv

getLength :: Int -> a -> IO Int
getLength soFar _ = return $ soFar+1

updateHistories :: Char                                 -- process ID
                -> M.Map (L.ByteString) L.ByteString    -- current histories
                -> [L.ByteString]                       -- list of ingress msgs
                -> [L.ByteString]                       -- ready for delivery
                -> [L.ByteString]                       -- should forward
                -> (M.Map (L.ByteString) L.ByteString,
                    [L.ByteString],
                    [L.ByteString])
updateHistories _   histories []     dv fw = (histories, dv, fw)
updateHistories pId histories (m:xm) dv fw =
    updateHistories pId newHistories xm newDv newFw
    where
        (content, source, oldRemoteMsgHist) = deserializeMessage m
        key = content
        -- if the source is not part of the remote history, add it
        remoteMsgHist = if C.notElem source oldRemoteMsgHist
                            then C.cons source oldRemoteMsgHist
                            else oldRemoteMsgHist
        localMsgHist = M.findWithDefault L.empty key histories
        -- compute the concatenated message histories
        ccMsgHistories = L.sort $ L.append localMsgHist $
                            L.concatMap (\v -> if L.elem v localMsgHist
                                                    then L.empty
                                                    else L.singleton v)
                            remoteMsgHist
        newHistories =
            M.alter (\_ -> Just ccMsgHistories) key histories
        -- messages ready for delivery
        newDv = if L.length ccMsgHistories >= 3
                            then content:dv
                            else dv
        -- messages that shall be forwarded
        newFwMessage = serializeForwardedMessage content pId ccMsgHistories
        newFw = if (C.notElem pId ccMsgHistories)
                   || (C.notElem source oldRemoteMsgHist)
                   || (oldRemoteMsgHist /= ccMsgHistories)
                   || (localMsgHist /= ccMsgHistories)
                        then newFwMessage:fw
                        else fw


addEMsgsToHistories :: [L.ByteString]                       -- egress messages
                    -> M.Map (L.ByteString) L.ByteString    -- current histories
                    -> M.Map (L.ByteString) L.ByteString    -- updated histories
addEMsgsToHistories []     histories = histories
addEMsgsToHistories (m:xm) histories =
    addEMsgsToHistories xm newHistories
    where
        key = m
        value = L.empty
        newHistories = M.insert key value histories


updateForward ::
    [L.ByteString]                              -- new egress messages
    -> [L.ByteString]                           -- ingress msgs to be forwarded
    -> HashTable L.ByteString L.ByteString      -- current fw
    -> IO ()
updateForward [] [] _ = return ()
updateForward em im fw = do
    -- putStrLn $ "Adding to forward the following e " ++ show (em)
    mapM_ (\m -> H.insert fw m L.empty) em
    -- putStrLn $ "Adding to forward the following i " ++ show (im)
    mapM_ (\m -> do
                    let (con, _, hist) = deserializeMessage m
                    H.insert fw con hist) im
    return ()


handleBroadcast ::
    HashTable L.ByteString L.ByteString         -- current forward
    -> Char                                     -- process id
    -> [Socket]                                 -- all egress sockets
    -> IO ()
handleBroadcast forward pId eSockets = do
    H.mapM_ (\(k, v) -> broadcastOnce (k,v) pId eSockets
                        >> if L.length v == 5
                            then H.delete forward k
                            else return ()) forward
    return ()


handleDelivery ::
    Handle
    -> [L.ByteString]
    -> HashTable Char DeliveryGuard
    -> IO ()
handleDelivery _      []     _ = return ()
handleDelivery handle (m:xm) devRecords = do
    let (allSeqNr, origin) = deserializeMessageContentB m
    mGuard <- H.lookup devRecords origin
    let guard = fromJust mGuard
    let (can, newGuard) = canDeliverRange guard (head allSeqNr) (last allSeqNr)
    if can
        then
            mapM_ (\s -> hPrintf handle "d %c %d\n" origin s) allSeqNr
            >> H.insert devRecords origin newGuard
            >> handleDelivery handle xm devRecords
        else
            handleDelivery handle xm devRecords

compactHistories ::
    [L.ByteString]
    -> M.Map (L.ByteString) L.ByteString
    -> M.Map (L.ByteString) L.ByteString
compactHistories []     hist = hist
compactHistories (m:xm) hist = compactHistories xm $ M.delete m hist