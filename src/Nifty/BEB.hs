module Nifty.BEB where


import Network.Socket                       hiding (send)
import Network.Socket.ByteString.Lazy       (sendAll)
import qualified Data.Set                   as S
import qualified Data.ByteString.Lazy       as L
import qualified Data.ByteString.Lazy.Char8 as C
-- import System.IO
-- import System.IO.Error
import Control.Exception


broadcastOnce :: S.Set (L.ByteString, Char)
                 -> Char 
                 -> [Socket]
                 -> IO ()
broadcastOnce fw pId eSockets = do
    if S.null fw 
        then return ()
        else do 
            _ <- mapM (\s -> (sendWithError s msg) `catch` hndl) eSockets
            putStrLn $ "Sending message " ++ (show msg) ++ " to all"
            broadcastOnce tailFw pId eSockets
    where
        tailFw = S.deleteAt 0 fw
        msg = assembleMessage (S.elemAt 0 fw) pId


sendWithError :: Socket -> L.ByteString -> IO ()
sendWithError sock msg = do
    sendAll sock msg


hndl :: IOError -> IO ()  
hndl _ = 
    -- putStrLn $ "Error sending on socket; some processes are down? " ++( show e)
    return ()


assembleMessage :: (L.ByteString, Char) -> Char -> L.ByteString
assembleMessage (seqNr, origin) procId =
    C.append seqNr $ C.pack (' ':origin:' ':procId:[])