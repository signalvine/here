{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-missing-fields #-}

-- | Here docs and string interpolation via quasiquotation
module Data.String.Here (here, hereI, hereLit) where

import Data.Char
import Data.Functor
import Data.Maybe
import Data.Typeable

import Language.Haskell.Meta
import Language.Haskell.TH
import Language.Haskell.TH.Quote

import Text.Parsec
import Text.Parsec.String

-- | Quote a here doc, stripping leading and trailing whitespace
here :: QuasiQuoter
here = QuasiQuoter {quoteExp = stringE . trim}

-- | Quote a here doc literally, with no whitespace stripping
hereLit :: QuasiQuoter
hereLit = QuasiQuoter {quoteExp = stringE}

trim :: String -> String
trim = trimTail . dropWhile isSpace

trimTail :: String -> String
trimTail "" = ""
trimTail s = take (lastNonBlank s) s
  where lastNonBlank = (+1) . fst . foldl acc (0, 0)
        acc (l, n) c | isSpace c = (l, n + 1)
                     | otherwise = (n, n + 1)

-- | Quote a here doc with embedded antiquoted expressions
--
-- Any expression occurring between @${@ and @}@ (for which the type must have
-- 'Show' and 'Typeable' instances) will be interpolated into the quoted
-- string.
hereI :: QuasiQuoter
hereI = QuasiQuoter {quoteExp = quoteInterp}

data StringPart = Lit String | Anti (Q Exp)

quoteInterp :: String -> Q Exp
quoteInterp s = either (handleError s) combineParts (parseInterp s)

handleError :: String -> ParseError -> Q Exp
handleError expStr parseError = error $
  "Failed to parse interpolated expression in string: "
    ++ expStr
    ++ "\n"
    ++ show parseError

combineParts :: [StringPart] -> Q Exp
combineParts = combine . map toExpQ
  where
    toExpQ (Lit s) = stringE s
    toExpQ (Anti expq) = [|toString $expq|]
    combine [] = stringE ""
    combine parts = foldr1 (\subExpr acc -> [|$subExpr ++ $acc|]) parts

toString :: (Show a, Typeable a) => a -> String
toString x = fromMaybe (show x) (cast x)

parseInterp :: String -> Either ParseError [StringPart]
parseInterp = parse p_interp ""

p_interp :: Parser [StringPart]
p_interp = manyTill p_stringPart eof

p_stringPart :: Parser StringPart
p_stringPart = try p_anti <|> p_lit

p_anti :: Parser StringPart
p_anti = Anti <$> between p_antiOpen p_antiClose p_antiExpr

p_antiOpen :: Parser String
p_antiOpen = string "${"

p_antiClose :: Parser String
p_antiClose = string "}"

p_antiExpr :: Parser (Q Exp)
p_antiExpr = manyTill anyChar (lookAhead p_antiClose)
         >>= either fail (return . return) . parseExp

p_lit :: Parser StringPart
p_lit = Lit
    <$> (try (manyTill anyChar $ lookAhead p_antiOpen) <|> manyTill anyChar eof)
