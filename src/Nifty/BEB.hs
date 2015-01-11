module Nifty.BEB where


import Nifty.Message

import Control.Exception
import Network.Socket                       hiding (send)
import Network.Socket.ByteString       (sendAll)
import qualified Data.ByteString       as L


broadcastOnce :: (L.ByteString, L.ByteString)   -- (message content, history)
                 -> Char
                 -> [Socket]
                 -> IO ()
broadcastOnce m pId eSockets = do
    broadcastOneMessage (assembleMessage m) eSockets
    where
        assembleMessage (c, h) =
            serializeForwardedMessage c pId h

broadcastOneMessage ::
    L.ByteString
    -> [Socket]
    -> IO ()
broadcastOneMessage m sos = do
    -- putStrLn $ "Sending message " ++ (show m) ++ " to all"
    mapM_ (\s -> (sendWithError s m) `catch` hndl) sos


sendWithError ::
    Socket
    -> L.ByteString
    -> IO ()
sendWithError sock msg = do sendAll sock msg


hndl :: IOError -> IO ()
hndl _ =
    -- putStrLn $ "Error sending on socket; some processes are down? " ++( show e)
    return ()