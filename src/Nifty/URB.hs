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
import qualified Data.ByteString.Lazy       as L
import qualified Data.Map.Strict            as M
import qualified Data.Set                   as S
import qualified Data.ByteString.Lazy.Char8 as C


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


messageCollector :: Char                                    -- process ID
                    -> BoundedChan (L.ByteString)                    -- egress channel
                    -> [Socket]                             -- egress sockets
                    -> TChan (L.ByteString)                 -- ingress channel
                    -> M.Map (L.ByteString) [Char]    -- ack
                    -> S.Set (L.ByteString)           -- forward
                    -> IO ()
messageCollector pId eChan eSockets iChan ack fw = do
    allIMsg <- collectAvailableIMsg iChan [] iMsgCollectorLimit
    putStrLn $ "Available igress messages: " ++ (show allIMsg)
    let (toDeliver, newAck, newFw) = readyForDelivery allIMsg ack fw []
    putStrLn $ "ACK = " ++ (show newAck)
    putStrLn $ "FW = " ++ (show newFw)
    _ <- mapM deliverURB toDeliver
    allEMsg <- collectAvailableEMsg eChan [] egressChanLength
    putStrLn $ "Available egress messages: " ++ (show allEMsg)
    let newerFw = addEgressMessagesToFw allEMsg newFw
    broadcastOnce newerFw pId eSockets
    threadDelay 10000000
    messageCollector pId eChan eSockets iChan newAck newerFw


readyForDelivery :: [L.ByteString]
                    -> M.Map (L.ByteString) [Char]
                    -> S.Set (L.ByteString)
                    -> [L.ByteString]                       -- accumulator
                    -> ( [L.ByteString]
                        , M.Map (L.ByteString) [Char]
                        , S.Set (L.ByteString) )
readyForDelivery []     ack fw accum = (accum, ack, fw)
readyForDelivery (m:xm) ack fw accum =
    if (enoughAck == True)
        then readyForDelivery xm newAckDelete newFwDelete (m:accum)
        else readyForDelivery xm newAckInsert newFwInsert accum
    where
        (pckdMsg, src) = bytestringToMessage m
        ackForM = M.findWithDefault [] pckdMsg ack
        enoughAck = if (length ackForM + 1) >= 3
                        then True
                        else False
        newAckDelete = M.delete pckdMsg ack
        newAckInsert =
            if notElem src ackForM
                then M.insert pckdMsg (src:ackForM) ack
                else ack
        newFwInsert = S.insert pckdMsg fw
        newFwDelete = S.delete pckdMsg fw


bytestringToMessage :: L.ByteString -> (L.ByteString, Char)
bytestringToMessage bs =
    (C.takeWhile (\c -> c /= ' ') bs, C.last $ w!!1)
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