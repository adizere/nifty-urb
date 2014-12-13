module Nifty.BEB where


import Network.Socket                       hiding (send)
import Network.Socket.ByteString.Lazy       (sendAll)
import qualified Data.Set                   as S
import qualified Data.ByteString.Lazy       as L
import qualified Data.ByteString.Lazy.Char8 as C


broadcastOnce :: S.Set (L.ByteString, Char)
                 -> Int 
                 -> [Socket]
                 -> IO ()
broadcastOnce fw pId eSockets = do
    if S.null fw 
        then return ()
        else do 
            mapM (\s -> sendAll s msg) eSockets
            putStrLn $ "Sending message " ++ (show msg) ++ " to all"
            broadcastOnce tailFw pId eSockets
    where
        headFw = S.elemAt 0 fw
        tailFw = S.deleteAt 0 fw
        msg = assembleMessage headFw pId


assembleMessage :: (L.ByteString, Char) -> Int -> L.ByteString
assembleMessage (seqNr, origin) procId =
    C.pack (sSeqNr ++ " " ++ [origin] ++ " " ++ sProcId)
    where
        sSeqNr = show seqNr
        sProcId = show procId