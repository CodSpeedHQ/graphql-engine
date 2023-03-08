-- | This module is inspired by @casing@ package. Instead of @String@ this
--  package uses @Data.Text.Text@
--
-- - @PascalCase@ - no spacing between words, first letter in word is
--    uppercase, all others are lowercase.
-- - @camelCase@ - like @PascalCase@, but the very first letter is lowercase.
-- - @snake_Case@ - underscores delimit words, case is unrestricted.
module Data.Text.Casing
  ( -- * Types
    GQLNameIdentifier,
    namePrefix,
    nameSuffixes,
    NameOrigin (..),

    -- * @Data.Text@ converters
    toCamelT,
    toPascalT,
    toSnakeT,

    -- * GQLName generators
    toCamelG,
    toPascalG,
    toSnakeG,

    -- * Shorthand functions for @Data.Text@
    snakeToCamel,
    snakeToPascal,

    -- * Parser for @Data.Text@
    fromSnake,

    -- * Transformers
    transformNameWith,
    transformGQLSuffixWith,
    transformGQLIdentifierWith,

    -- * Helpers
    fromTupleWith,
    fromNameWith,
    fromAutogeneratedName,
    fromCustomName,
    fromAutogeneratedTuple,
    fromCustomTuple,
    fromNonEmptyList,
    identifierToList,
    lowerFirstChar,
    transformPrefixAndSuffixAndConcat,
    upperFirstChar,
  )
where

import Data.List (intersperse)
import Data.List.NonEmpty qualified as NE
import Data.Text qualified as T
import Hasura.Prelude
import Language.GraphQL.Draft.Syntax qualified as G

type NameWithOrigin = (G.Name, NameOrigin)

type NameSuffixWithOrigin = (G.NameSuffix, NameOrigin)

-- | An opaque type, representing a parsed identifier with prefix and suffixes.
data GQLNameIdentifier = GQLNameIdentifier
  { namePrefix :: NameWithOrigin,
    nameSuffixes :: [NameSuffixWithOrigin]
    -- Using Vectors instead of list may improve memory uses
  }
  deriving (Show, Ord, Eq, Generic)

instance Hashable GQLNameIdentifier

-- | Represents the origin of a name entity.
--
--      * `CustomName` represents a custom user provided name
--      * `AutogeneratedName` represents a name which is generated by Hasura
--
--   For a custom table name @foo@, the select by pk field name elements:
--
--      * @foo@ is a `CustomName`
--      * @by@ is an `AutogeneratedName`
--      * @pk@ is an `AutogeneratedName`
--
--   However, for a table name @foo_bar@, the select by pk field name elements
--   @foo@, @bar@, @by@ and @pk@ are all `AutogeneratedName`
data NameOrigin = CustomName | AutogeneratedName
  deriving (Show, Eq, Ord, Generic)

instance Hashable NameOrigin

instance (Semigroup GQLNameIdentifier) where
  GQLNameIdentifier pref1 suffs1 <> GQLNameIdentifier pref2 suffs2 = GQLNameIdentifier pref1 (suffs1 ++ first G.convertNameToSuffix pref2 : suffs2)

fromTupleWith :: NameOrigin -> (G.Name, [G.NameSuffix]) -> GQLNameIdentifier
fromTupleWith o (pref, suffs) = GQLNameIdentifier (pref, o) (fmap (,o) suffs)

fromNameWith :: NameOrigin -> G.Name -> GQLNameIdentifier
fromNameWith o n = GQLNameIdentifier (n, o) []

fromAutogeneratedName :: G.Name -> GQLNameIdentifier
fromAutogeneratedName = fromNameWith AutogeneratedName

fromCustomName :: G.Name -> GQLNameIdentifier
fromCustomName = fromNameWith CustomName

fromAutogeneratedTuple :: (G.Name, [G.NameSuffix]) -> GQLNameIdentifier
fromAutogeneratedTuple = fromTupleWith AutogeneratedName

fromCustomTuple :: (G.Name, [G.NameSuffix]) -> GQLNameIdentifier
fromCustomTuple = fromTupleWith CustomName

fromNonEmptyList :: NonEmpty NameWithOrigin -> GQLNameIdentifier
fromNonEmptyList neList = GQLNameIdentifier (NE.head neList) (map (first G.convertNameToSuffix) (NE.tail neList))

-- | transforms a graphql name with a transforming function
--
-- Note: This will return the graphql name without transformation if the
-- transformed name is not a valid GraphQL identifier
transformNameWith :: (Text -> Text) -> G.Name -> G.Name
transformNameWith f name = fromMaybe name (G.mkName (f (G.unName name)))

-- | same as `transformNameWith` but will not transform if the name is a custom name
transformNameAndOriginWith :: (Text -> Text) -> NameWithOrigin -> NameWithOrigin
transformNameAndOriginWith _ n@(_, CustomName) = n
transformNameAndOriginWith f (name, AutogeneratedName) = (transformNameWith f name, AutogeneratedName)

-- | similar to @transformNameWith@ but transforms @NameSuffix@ instead of
--  @Name@
transformGQLSuffixWith :: (Text -> Text) -> G.NameSuffix -> G.NameSuffix
transformGQLSuffixWith f suffix = fromMaybe suffix (G.mkNameSuffix (f (G.unNameSuffix suffix)))

-- | This is essentially same as @second transformGQLSuffixWith@
transformGQLSuffixAndOriginWith :: (Text -> Text) -> NameSuffixWithOrigin -> NameSuffixWithOrigin
transformGQLSuffixAndOriginWith f (suffix, orig) = (transformGQLSuffixWith f suffix, orig)

-- | transforms a `GQLNameIdentifier`; this will apply the transformations on prefix as well as suffixes
transformGQLIdentifierWith :: (Text -> Text) -> GQLNameIdentifier -> GQLNameIdentifier
transformGQLIdentifierWith f (GQLNameIdentifier pref suffs) = GQLNameIdentifier (transformNameAndOriginWith f pref) (fmap (transformGQLSuffixAndOriginWith f) suffs)

-- | converts identifiers to @Text@ (i.e. @unName@s and @unNameSuffix@s
--  identifiers)
identifierToList :: GQLNameIdentifier -> [Text]
identifierToList (GQLNameIdentifier (pref, _) (suffs)) = (G.unName pref) : (map (G.unNameSuffix . fst) suffs)

-- | To @snake_case@ for @Data.Text@
--
-- >>> toSnakeT ["my","random","text","list"]
-- "my_random_text_list"
toSnakeT :: [Text] -> Text
toSnakeT = T.concat . intersperse "_"

-- | To @PascalCase@ for @Data.Text@
--
-- >>> toPascalT ["my","random","text","list"]
-- "MyRandomTextList"
toPascalT :: [Text] -> Text
toPascalT = T.concat . map upperFirstChar

-- | To @camelCase@ for @Data.Text@
--
-- >>> toCamelT ["my","random","text","list"]
-- "myRandomTextList"
toCamelT :: [Text] -> Text
toCamelT ([]) = ""
toCamelT ((x : xs)) = (lowerFirstChar x) <> T.concat (map upperFirstChar xs)

-- | To @snake_case@ for @GQLNameIdentifier@
toSnakeG :: GQLNameIdentifier -> G.Name
toSnakeG (GQLNameIdentifier (pref, _) suff) = G.addSuffixes pref (map (transformGQLSuffixWith ("_" <>) . fst) suff)

-- | To @PascalCase@ for @GQLNameIdentifier@
toPascalG :: GQLNameIdentifier -> G.Name
toPascalG gqlIdentifier = transformPrefixAndSuffixAndConcat gqlIdentifier upperFirstChar upperFirstChar

-- | To @camelCase@ for @GQLNameIdentifier@
toCamelG :: GQLNameIdentifier -> G.Name
toCamelG gqlIdentifier = transformPrefixAndSuffixAndConcat gqlIdentifier lowerFirstChar upperFirstChar

-- | Transforms @GQLNameIdentifier@ and returns a @G.Name@
transformPrefixAndSuffixAndConcat :: GQLNameIdentifier -> (T.Text -> T.Text) -> (T.Text -> T.Text) -> G.Name
transformPrefixAndSuffixAndConcat (GQLNameIdentifier pref suff) prefixTransformer suffixTransformer =
  G.addSuffixes (fst (transformNameAndOriginWith prefixTransformer pref)) (map (fst . transformGQLSuffixAndOriginWith suffixTransformer) suff)

-- @fromSnake@ is used in splitting the schema/table names separated by @_@
-- For global naming conventions:
-- We do not want to capture the underscore in the begining as a delimiter
-- and want to store it as it is. A user might have a schema that starts with
-- an underscore (we want to treat it as a part of the schema name rather
-- than a delimiter)
--

-- | Convert from @snake_cased@
--
-- >>> fromSnake "_hello_world_foo"
-- ["_hello","world","foo"]
fromSnake :: Text -> [Text]
fromSnake t = case T.splitOn "_" t of
  ("" : x : xs) -> ("_" <> x) : xs
  bs -> bs

-- | Directly convert to @PascalCase@ through 'fromSnake'
snakeToPascal :: Text -> Text
snakeToPascal = toPascalT . fromSnake

-- | Directly convert to @camelCase@ through 'fromSnake'
snakeToCamel :: Text -> Text
snakeToCamel = toCamelT . fromSnake

-- Internal helpers

-- | An internal helper function to lowercase the first character
lowerFirstChar :: Text -> Text
lowerFirstChar t = T.toLower (T.take 1 t) <> T.drop 1 t

-- | An internal helper function to uppercase the first character
upperFirstChar :: Text -> Text
upperFirstChar t = T.toUpper (T.take 1 t) <> T.drop 1 t
