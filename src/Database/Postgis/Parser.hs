{-# LANGUAGE OverloadedStrings, TemplateHaskell #-}

module Database.Postgis.Simple.Parser  where

import Database.Postgis.Utils
import Database.Postgis.WKBTypes
--
import Data.Serialize
import Development.Placeholders
import qualified Data.ByteString as BS
import Data.ByteString.Lex.Integral
import Data.Bits
import qualified Data.Vector as V
import Control.Applicative
import Data.Binary.IEEE754
import System.Endian

class Hexable a where
  toHex :: a -> BS.ByteString
  fromHex :: BS.ByteString -> a

instance Hexable Int where
  toHex = toHexInt
  fromHex = fromHexInt

instance Hexable Double where
  fromHex = wordToDouble . fromHexInt 
  toHex = toHexInt . doubleToWord

putGeometry h g = do
  put h
  
instance Serialize Geometry where
  put (PointGeometry p) = put p 
  put (LineStringGeometry ls) = put ls
  put (PolygonGeometry p) = put p
  put (
     
-- todo: Validate geometry should compare header w/ geo characteristics
  get = do
    header <- get
    let tVal = (_geoType header) .&. ewkbTypeOffset
    case tVal of
      1 -> PointGeometry <$> parsePointGeometry header
      2 -> LineStringGeometry <$> parseLineString header
      3 -> PolygonGeometry <$> parsePolygon header
      4 -> MultiPointGeometry <$> parseMultiPoint header
      5 -> MultiLineStringGeometry <$> parseMultiLineString header
      6 -> MultiPolygonGeometry <$> parseMultiPolygon header
      {-7 -> parseGeoCollection header-}
      _ -> error "not yet implemented"


instance Serialize Header where 
  put (Header bo gt sr) = do
    put bo
    writeNum bo gt 
    writeMaybeNum bo sr
  get = do
    or <- get	
    t <- parseNum or
    srid <- if t .&. wkbSRID > 0 then Just <$> parseNum or else return Nothing 
    return $ Header or t srid

instance Serialize Endianness where
  put BigEndian = putByteString $ toHex (0::Int)
  put LittleEndian = putByteString $ toHex (1::Int)
  get = do
    bs <- getByteString 2
    case fromHex bs :: Int of
      0 -> return BigEndian
      1 -> return LittleEndian
      _ -> error $ "not an endian: " ++ show bs

parsePoint :: Header -> Get Point
parsePoint (Header e gt sr) = do
	let hasM = if (gt .&. wkbM) > 0 then True else False 
	    hasZ = if (gt .&. wkbZ) > 0 then True else False
	x <- parseNum e
	y <- parseNum e
	m <- if hasM then Just <$> parseNum e else return Nothing
	z <- if hasZ then Just <$> parseNum e else return Nothing
	return $ Point x y m z

writePoint :: Header -> Putter Point 
writePoint (Header bo gt sr) (Point x y m z) = do
  writeNum bo x
  writeNum bo y
  writeMaybeNum bo m
  writeMaybeNum bo z
  

type LineSegment = (Int, V.Vector Point)

parseSegment :: Header ->  Get LineSegment
parseSegment head = do
  n <- parseNum $ _byteOrder head
  ps <- V.replicateM n $ parsePoint head
  return $ (n, ps)

parseRing :: Header -> Get LinearRing
parseRing head = (LinearRing <$> fst <*> snd) <$> parseSegment head


parsePointGeometry :: Header -> Get Point
parsePointGeometry head = do
	p <- parsePoint head
	return $ PointGeometry head p

writePointGeometry :: Putter Point
writePointGeometry (Point head p) = do
  pu
  
   

  


writeLineString :: Header -> Putter LineString
writeLineString (Header bo gt sr) = 

parseLineString :: Header -> Get LineString
parseLineString head = ((LineStringGeometry head) <$> fst <*> snd) <$> parseSegment head

parseMulti ::  Serialize a => (Int -> V.Vector a -> b) -> Header -> Get b
parseMulti cons head = do
  n <- parseNum $ _byteOrder head
  ps <- V.replicateM n get
  return $ cons n ps

parsePolygon :: Header -> Get Polygon
parsePolygon head = do
  n <- parseNum $ _byteOrder head
  vs <- V.replicateM n $ parseRing head  
  return $ PolygonGeometry head n vs 
 
parseMultiPoint :: Header -> Get MultiPoint
parseMultiPoint = parseMulti MultiPointGeometry

parseMultiLineString :: Header -> Get MultiLineString
parseMultiLineString = parseMulti MultiLineStringGeometry
 
parseMultiPolygon :: Header -> Get MultiPolygon
parseMultiPolygon = parseMulti MultiPolygonGeometry

parseNum :: (Num a, Hexable a) => Endianness -> Get a
parseNum BigEndian = fromHex <$> get  
parseNum LittleEndian = (fromHex . readLittleEndian) <$> get 

writeNum :: (Num a, Hexable a) => Endianness -> Putter a
writeNum BigEndian n = put $ toHex n
writeNum LittleEndian n = (put . readLittleEndian . toHex) n

writeMaybeNum :: (Num a, Hexable a) => Endianness -> Putter (Maybe a)
writeMaybeNum end (Just n)  = writeNum end n 
writeMaybeNum end Nothing = return () 

toHexInt :: Integral a => a -> BS.ByteString
toHexInt i = case packHexadecimal i of
    Just bs -> bs
    Nothing -> error "Cannot create bytestring"

fromHexInt :: Integral a => BS.ByteString -> a
fromHexInt bs = case readHexadecimal bs of
    Just (v, r) -> v
    Nothing -> error "Cannot parse hexadecimal"

readLittleEndian :: BS.ByteString -> BS.ByteString
readLittleEndian bs = BS.concat . reverse $ splitEvery bs
  where
    splitEvery bs = 
      let (first, rest) = BS.splitAt 2 bs in 
      if BS.null bs then [] else first : (splitEvery rest)
 