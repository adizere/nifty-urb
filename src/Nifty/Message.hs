module Nifty.Message where

import qualified Data.ByteString       as L
import qualified Data.ByteString.Char8 as C
import Data.Maybe


serializeOriginMessageContent ::
    Int                 -- sequence number
    -> Int              -- origin
    -> L.ByteString     -- resulting message serialized
serializeOriginMessageContent seqNr pId =
    C.pack (show seqNr ++ show pId)


serializeOriginMessageContentB ::
    L.ByteString
    -> Int
    -> L.ByteString
serializeOriginMessageContentB seqNr pId =
    C.append seqNr $ C.pack (show pId)


deserializeMessageContentB ::
    L.ByteString
    -> ([Integer], Char)
deserializeMessageContentB content =
    ([x | x <- [chunk1Int..chunk2Int]], origin)
    where
        chunks = C.span (\c -> c /= '-') content
        chunk1Int = fst $ fromJust (C.readInteger (fst chunks))
        (chunk2, origin) = fromJust $ C.unsnoc (C.drop 1 (snd chunks))
        chunk2Int = fst $ fromJust $ C.readInteger chunk2

serializeForwardedMessage ::
    L.ByteString        -- message content
    -> Char             -- source = current process ID
    -> L.ByteString     -- histories
    -> L.ByteString
serializeForwardedMessage content pId histories =
    C.append (C.snoc (C.snoc (C.snoc content ' ') pId) ' ') histories


deserializeMessage ::
    L.ByteString        -- raw message
    -> (L.ByteString,   -- message content, i.e. seqNr concatenated with origin
        Char,           -- source, i.e. the index of sender
        L.ByteString)   -- history
deserializeMessage bs =
    (w!!0, C.last $ w!!1, history)
    where
        w = C.words bs
        history = if length w > 2
                        then w!!2
                        else L.empty


deserializeMessageContent ::
    L.ByteString                    -- message content: seqNr concat with origin
    -> Maybe (L.ByteString, Char)   -- (seqNr, origin)
deserializeMessageContent content = C.unsnoc content