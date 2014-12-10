module Nifty.URB where


import Nifty.PointToPointLink

-- import Control.Concurrent (threadDelay)

import Control.Concurrent.STM.TChan
import Control.Concurrent.BoundedChan
import Data.Word                            (Word8)
import Control.Concurrent.MVar              (takeMVar, MVar)
import Control.Concurrent                   (forkIO)
import Control.Monad.STM                    (atomically)
import Network.Socket                       hiding (recv)
import qualified Data.ByteString.Lazy       as L
import qualified Data.Map.Strict            as M
import qualified Data.Sequence              as S
import qualified Data.ByteString.Lazy.Char8 as C


egressChanLength :: Int
egressChanLength = 10

iMsgCollectorLimit :: Int
iMsgCollectorLimit = 100

startURB :: (Int, [(String, Int)], Int) -> MVar (Int) -> IO ()
startURB (procId, ipsPorts, msgCnt) stMVar = do
    putStrLn "Waiting.. "
    eChan <- setupNetwork procId ipsPorts
    takeMVar stMVar >> startURBroadcast eChan msgCnt


startURBroadcast :: BoundedChan (L.ByteString) -> Int -> IO ()
startURBroadcast chan msgCnt = do
    putStrLn "I can start broadcasting.."
    let messages = C.pack "1 1"
    putStrLn $ show $ bytestringToMessage messages
    -- mapM (\s -> send s "hejhej" >>= (\b -> putStrLn $ "Sent bytes" ++ (show b))) eSockets
    return ()


-- urbBroadcast :: L.ByteString -> 

setupNetwork :: Int -> [(String, Int)] -> IO (BoundedChan L.ByteString)
setupNetwork pId ipsPorts =
    establishPTPLinks pAddr foreignAddresses >>= setupMessageCollector pId
    where
        foreignAddresses = [ ipsPorts!!fId | fId <- [0..4], fId /= (pId-1) ]
        pAddr = ipsPorts!!(pId-1)


setupMessageCollector :: Int 
                         -> (TChan L.ByteString, [Socket])
                         -> IO (BoundedChan L.ByteString)
setupMessageCollector pId (iChan, eSockets) = do
    eChan <- newBoundedChan egressChanLength :: IO (BoundedChan L.ByteString)
    _ <- forkIO (messageCollector eChan eSockets iChan M.empty S.empty)
    return eChan


messageCollector :: BoundedChan (L.ByteString)              -- egress channel
                    -> [Socket]                             -- egress sockets
                    -> TChan (L.ByteString)                 -- ingress channel
                    -> M.Map (L.ByteString, Word8) [Word8]  -- ack
                    -> S.Seq (L.ByteString, Word8)          -- forward
                    -> IO ()
messageCollector eChan eSockets iChan ack fw = do
    allIMsg <- collectAvailableIMsg iChan [] iMsgCollectorLimit
    putStrLn $ "Available igress messages: " ++ (show allIMsg)
    let (toDeliver, newAck, newFw) = readyForDelivery allIMsg ack fw []
    _ <- mapM deliverURB toDeliver
    return ()


readyForDelivery :: [L.ByteString] 
                    -> M.Map (L.ByteString, Word8) [Word8]
                    -> S.Seq (L.ByteString, Word8)
                    -> [L.ByteString]                       -- accumulator
                    -> ( [L.ByteString]
                        , M.Map (L.ByteString, Word8) [Word8]
                        , S.Seq (L.ByteString, Word8) )
readyForDelivery []     ack fw accum = (accum, ack, fw)
readyForDelivery (m:xm) ack fw accum =
    -- if enoughAck $ bytestringToMessage msg
    --     then expression
    --     else expression
    (xm, ack, fw)
    -- where
    --     enoughAck m =


bytestringToMessage :: L.ByteString -> (L.ByteString, Word8)
bytestringToMessage bs =
    (value, source)
    where
        value = L.init bs
        source = L.last bs



collectAvailableIMsg :: TChan (L.ByteString)    -- input channel
                        -> [L.ByteString]       -- accumulator
                        -> Int                  -- limit
                        -> IO ([L.ByteString])
collectAvailableIMsg iChan acc 0 = return acc
collectAvailableIMsg iChan acc limit = do
    maybeIMsg <- atomically $ tryReadTChan iChan
    case maybeIMsg of
        Just iMsg   -> collectAvailableIMsg iChan (iMsg:acc) (limit-1)
        Nothing     -> return acc


deliverURB :: L.ByteString -> IO ()
deliverURB msg = putStrLn $ "deliveree: " ++  (show msg)