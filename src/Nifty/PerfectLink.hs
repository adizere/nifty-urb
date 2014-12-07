module Nifty.PerfectLink where


import Network.Socket hiding (recv)
import qualified Data.ByteString.Lazy as L
import Network.Socket.ByteString.Lazy (recv)
import Control.Concurrent.Chan
import Control.Monad (forever)
import Control.Concurrent (forkIO)
import Control.Exception (bracket)


establishPL :: (String, Int) 
               -> [(String, Int)]
               -> IO (Chan L.ByteString, [Socket])
establishPL (mIp, mPort) fAddresses = do
    -- putStrLn $ "Gonna bind ingress socket to " ++ mIp ++ (show mPort)  
    chan <- newChan :: IO (Chan L.ByteString)
    _ <- forkIO (bindIngressSocket mIp mPort chan)
    mapM getEgressSocket fAddresses >>= (\list -> return (chan, list))


getEgressSocket :: (String, Int) -> IO Socket
getEgressSocket (fIp, fPort) = do
    putStrLn $ "Getting an egress socket for " ++ fIp ++ (show fPort)
    (serveraddr:_) <- getAddrInfo Nothing (Just fIp) (Just $ show fPort)
    s <- socket (addrFamily serveraddr) Datagram defaultProtocol
    connect s (addrAddress serveraddr) >> return s


-- binds a socket and writes every received message to a Chan
bindIngressSocket :: String -> Int -> Chan (L.ByteString) -> IO ()
bindIngressSocket ip port chan = bracket bindMe close handler
    where 
        bindMe = do
            (serveraddr:_) <- getAddrInfo 
                                (Just (defaultHints 
                                        {addrFlags = [ AI_ADDRCONFIG
                                                     , AI_NUMERICHOST]}))
                                (Just ip) 
                                (Just $ show port)
            sock <- socket (addrFamily serveraddr) Datagram defaultProtocol
            bindSocket sock (addrAddress serveraddr) >> return sock
        handler = receiveFromPL chan


receiveFromPL :: Chan (L.ByteString) -> Socket -> IO ()
receiveFromPL chan sock =
    forever $ do
        msg <- recv sock 256
        putStrLn $ "Got a message lol " ++ (show msg)
        writeChan chan msg


    -- threadDelay 1000000
    -- hFlush stdout
    -- mv <- tryTakeMVar stMVar
    -- case mv of 
    --     Just val -> do
    --         putStrLn $ "W: Interrupt Received. Killing the process."
    --         hFlush stdout
    --         return ()
    --     Nothing -> return ()