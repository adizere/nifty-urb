module Nifty.URB where


import Nifty.PointToPointLink
import Nifty.BEB

import Control.Concurrent.STM.TChan
import Control.Concurrent.BoundedChan
import Control.Concurrent                   (threadDelay)
import Control.Concurrent.MVar              (takeMVar, MVar)
import Control.Concurrent                   (forkIO)
import Control.Monad.STM                    (atomically)
import Network.Socket                       hiding (recv)
import Data.Maybe
import qualified Data.ByteString.Lazy       as L
import qualified Data.ByteString.Lazy.Char8 as C
import qualified Data.Map.Strict            as M
import qualified Data.Set                   as S
import qualified Data.Word                  as W


egressChanLength :: Int
egressChanLength = 10


iMsgCollectorLimit :: Int
iMsgCollectorLimit = 100


startURB :: (Int, [(String, Int)], Int) -> MVar (Int) -> IO ()
startURB (procId, ipsPorts, msgCnt) stMVar = do
    putStrLn "Waiting.. "
    eChan <- setupNetwork procId ipsPorts
    takeMVar stMVar >> startURBroadcast eChan procId msgCnt 1


startURBroadcast :: BoundedChan (L.ByteString) -> Int -> Int -> Int -> IO ()
startURBroadcast eChan procId (-1) seqNr = do
    putStrLn $ "I am broadcasting.. " ++ (show seqNr)
    writeChan eChan $ getEgressMessage seqNr procId
    startURBroadcast eChan procId (-1) (seqNr+1)

startURBroadcast _ _ 0 _ = return ()

startURBroadcast eChan procId msgCnt seqNr = do
    putStrLn $ "I am broadcasting.. " ++ (show seqNr)
    writeChan eChan $ getEgressMessage seqNr procId
    startURBroadcast eChan procId (msgCnt-1) (seqNr+1)

getEgressMessage :: Int -> Int -> L.ByteString
getEgressMessage seqNr pId =
    C.pack (show seqNr ++ show pId)


setupNetwork :: Int -> [(String, Int)] -> IO (BoundedChan L.ByteString)
setupNetwork pId ipsPorts =
    establishPTPLinks pAddr foreignAddresses
        >>= setupMessageCollector (head $ show pId)
    where
        foreignAddresses = [ ipsPorts!!fId | fId <- [0..4], fId /= (pId-1) ]
        pAddr = ipsPorts!!(pId-1)


setupMessageCollector :: Char
                         -> (TChan L.ByteString, [Socket])
                         -> IO (BoundedChan L.ByteString)
setupMessageCollector pId (iChan, eSockets) = do
    eChan <- newBoundedChan egressChanLength :: IO (BoundedChan L.ByteString)
    _ <- forkIO (messageCollector pId eChan eSockets iChan M.empty S.empty)
    return eChan


bytestringToMessage :: L.ByteString -> (L.ByteString, Char, L.ByteString)
bytestringToMessage bs =
    (C.takeWhile (\c -> c /= ' ') bs, C.last $ w!!1, w!!2)
    where
        w = C.words bs


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


addEgressMessagesToFw :: [L.ByteString]
                         -> S.Set (L.ByteString)    -- accumulator
                         -> S.Set (L.ByteString)
addEgressMessagesToFw []     fw     = fw
addEgressMessagesToFw (m:xm) fw     = addEgressMessagesToFw xm newFw
    where
        newFw = S.insert m fw


-- Skeleton for updated version:
messageCollector    :: Char                                 -- process ID
                    -> BoundedChan (L.ByteString)           -- egress channel
                    -> [Socket]                             -- egress sockets
                    -> TChan (L.ByteString)                 -- ingress channel
                    -> M.Map (L.ByteString) L.ByteString    -- histories
                    -> S.Set (L.ByteString)                 -- forward
                    -> IO ()
messageCollector pId eChan eSockets iChan histories fw = do
    allIMsg <- collectAvailableIMsg iChan [] iMsgCollectorLimit
    putStrLn $ "Fetched some ingress messages: " ++ (show allIMsg)
    let (newHistories, readyForDelivery) = updateHistories histories allIMsg []
    return ()


updateHistories :: M.Map (L.ByteString) L.ByteString    -- current histories
                -> [L.ByteString]                       -- list of ingress msgs
                -> [L.ByteString]                       -- accum for messages
                -> (M.Map (L.ByteString) L.ByteString, [L.ByteString])
updateHistories cHist []     accum  = (cHist, accum)
updateHistories cHist (m:xm) accum  =
    if (isJust mValue) && (L.length value >= 3)
        then updateHistories nHist xm $ key:accum
        else updateHistories nHist xm accum
    where
        (seqNr, origin, msgHist) = bytestringToMessage m
        key = C.snoc seqNr origin
        (mValue, nHist) = M.updateLookupWithKey mapValueConcat key cHist
        value = fromJust mValue
        mapValueConcat k mOldHist =
            -- concatenate the old and the new message history
            Just $ L.append mOldHist $ L.concatMap (\v -> if L.elem v mOldHist
                                                            then L.empty
                                                            else L.singleton v)
                                                   msgHist

-- -- use Map.unionWith to create the union of local histories and remote histories
-- updateHistories :: M.Map (L.ByteString) L.ByteString
--                    -> [L.ByteString]
--                    -> M.Map (L.ByteString) L.ByteString
-- updateHistories histories []        = histories
-- updateHistories histories (m:xm)    = updateHistories newHistories xm
--     where
--         localHist = M.findWithDefault S.empty m histories
--         updateHistories = M.

-- pseudo algo:
-- (msg, src, rHistory) <- read iChan
-- histories(msg) union with rHistory
-- if (procId notElem rHistory) || (src notElem rHistory)
--     then fw = fw union {msg, destination=src}
-- if |histories(msg)| >= 3
--     then deliver msg

-- msg <- read eChan
-- histories(msg) = {}
