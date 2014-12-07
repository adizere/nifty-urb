module Nifty.URB where


import Nifty.PerfectLink

import Control.Concurrent.MVar (takeMVar, MVar)
-- import Control.Concurrent (threadDelay)

import Network.Socket hiding (recv)
import qualified Data.ByteString.Lazy as L
-- import Network.Socket.ByteString.Lazy (sendAll)

import Control.Concurrent.Chan


startURB :: (Int, [(String, Int)], Int) -> MVar (Int) -> IO ()
startURB (procId, ipsPorts, msgCnt) stMVar = do
    putStrLn "Waiting.. "
    (iChan, eSockets) <- setupNetwork procId ipsPorts
    takeMVar stMVar >> startURBroadcast iChan eSockets msgCnt


startURBroadcast :: Chan L.ByteString -> [Socket] -> Int -> IO ()
startURBroadcast chan eSockets msgCnt = do
    putStrLn "I can start broadcasting.."
    mapM (\s -> send s "hejhej" >>= (\b -> putStrLn $ "Sent bytes" ++ (show b))) eSockets
    return ()


setupNetwork :: Int -> [(String, Int)] -> IO (Chan L.ByteString, [Socket])
setupNetwork pId ipsPorts =
    establishPL pAddr foreignAddresses
    where
        foreignAddresses = [ ipsPorts!!fId | fId <- [0..4], fId /= (pId-1) ]
        pAddr = ipsPorts!!(pId-1)


-- urBroadcast :: L.ByteString