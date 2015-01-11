module Nifty.PointToPointLink where


import qualified Data.ByteString       as L
import Control.Concurrent.STM.TChan
import Network.Socket                   hiding (recv)
import Network.Socket.ByteString   (recv)
import Control.Monad.STM                (atomically)
import Control.Monad                    (forever)
import Control.Concurrent               (forkIO)
import Control.Exception                (bracket)


establishPTPLinks :: (String, Int)  -- local address (of current process)
               -> [(String, Int)]   -- foreign addresses
               -> IO (TChan L.ByteString, [Socket])
establishPTPLinks (mIp, mPort) fAddresses = do
    -- we will channelise all the ingress messages through the iChan
    iChan <- atomically $ newTChan :: IO (TChan L.ByteString)
    _ <- forkIO (bindIngressSocket mIp mPort iChan)
    mapM getEgressSocket fAddresses >>= (\list -> return (iChan, list))


getEgressSocket :: (String, Int) -> IO Socket
getEgressSocket (fIp, fPort) = do
    -- putStrLn $ "Getting an egress socket for " ++ fIp ++ (show fPort)
    (serveraddr:_) <- getAddrInfo Nothing (Just fIp) (Just $ show fPort)
    s <- socket (addrFamily serveraddr) Datagram defaultProtocol
    connect s (addrAddress serveraddr) >> return s


-- binds a socket and writes every received message to a Chan
bindIngressSocket :: String -> Int -> TChan (L.ByteString) -> IO ()
bindIngressSocket ip port iChan = bracket bindMe close handler
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
        handler = channeliseIngressPTPMessages iChan


channeliseIngressPTPMessages :: TChan (L.ByteString) -> Socket -> IO ()
channeliseIngressPTPMessages iChan sock =
    forever $ do
        msg <- recv sock 256
        -- putStrLn $ "Got a message lol " ++ (show msg)
        atomically $ writeTChan iChan msg
        return ()