{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Micro.CBOR (serialise, deserialise) where

import Micro.Types

import Data.Binary.Serialise.CBOR.Class
import Data.Binary.Serialise.CBOR.Encoding
import Data.Binary.Serialise.CBOR.Decoding
import Data.Binary.Serialise.CBOR.Read
import Data.Binary.Serialise.CBOR.Write
import qualified Data.Binary.Get as Bin
import Data.Monoid

import qualified Data.ByteString.Lazy as BS
import qualified Data.ByteString.Lazy.Internal as BS
import qualified Data.ByteString.Builder as BS

#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
import Data.Word
#endif

serialise :: Tree -> BS.ByteString
serialise = BS.toLazyByteString . toBuilder . encode

deserialise :: BS.ByteString -> Tree
deserialise = feedAll (deserialiseIncremental decode)
  where
    feedAll (Bin.Done _ _ x)    _ = x
    feedAll (Bin.Partial k) lbs   = case lbs of
      BS.Chunk bs lbs' -> feedAll (k (Just bs)) lbs'
      BS.Empty         -> feedAll (k Nothing) BS.empty
    feedAll (Bin.Fail _ pos msg) _ =
      error ("Data.Binary.Get.runGet at position " ++ show pos ++ ": " ++ msg)

encodeCtr0 :: Word -> Encoding
encodeCtr2 :: (Serialise a, Serialise b) => Word -> a -> b -> Encoding

encodeCtr0 n     = encodeListLen 1 <> encode (n :: Word)
encodeCtr2 n a b = encodeListLen 3 <> encode (n :: Word) <> encode a <> encode b

{-# INLINE encodeCtr0 #-}
{-# INLINE encodeCtr2 #-}

{-# INLINE decodeCtrTag #-}
{-# INLINE decodeCtrBody0 #-}
{-# INLINE decodeCtrBody2 #-}

decodeCtrTag :: Decoder (Word, Int)
decodeCtrTag = (\len tag -> (tag, len)) <$> decodeListLen <*> decodeWord

decodeCtrBody0 :: Int -> a -> Decoder a
decodeCtrBody0 1 f = pure f
decodeCtrBody0 x _ = error $ "decodeCtrBody0: impossible tag " ++ show x

decodeCtrBody2
  :: (Serialise a, Serialise b) => Int -> (a -> b -> c) -> Decoder c
decodeCtrBody2 3 f = do x1 <- decode
                        x2 <- decode
                        return (f x1 x2)
decodeCtrBody2 x _ = error $ "decodeCtrBody2: impossible tag " ++ show x

instance Serialise Tree where
  encode Leaf       = encodeCtr0 1
  encode (Fork a b) = encodeCtr2 2 a b

  decode = do
    (t,l) <- decodeCtrTag
    case t of
      1 -> decodeCtrBody0 l Leaf
      2 -> decodeCtrBody2 l Fork
      x -> error $ "Serialise Tree: decode: impossible tag " ++ show x

