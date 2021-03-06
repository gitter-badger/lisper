import Control.Monad
import System.Environment
import System.IO
import Text.ParserCombinators.Parsec hiding (spaces)

data LispVal = Atom String
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | String String
             | Bool Bool

-- Helpers to retrieve haskell values from LispVal

-- [todo] Add input type to error message
-- [todo] Possibly auto generate unpack*
unpackNum :: LispVal -> Integer
unpackNum (Number n) = n
unpackNum _ = error "Cannot type cast Value to Number"

-- Helpers
unwords' :: [LispVal] -> String
unwords' = unwords . map show

instance Show LispVal where
    show (Atom x) = x
    show (List x) =
      case x of
       Atom "quote" : _ -> "'" ++ unwords' (tail x)
       _ -> "(" ++ unwords' x ++ ")"
    show (DottedList h t) = "(" ++ unwords' h ++ " . " ++ show t ++ ")"
    show (String s) = "\"" ++ s ++ "\""
    show (Number n) = show n
    show (Bool True) = "#t"
    show (Bool False) = "#f"

symbol :: Parser Char
symbol = oneOf "!#$%&|*+-/:<=>?@^_~"

spaces :: Parser()
spaces = skipMany1 space

parseString :: Parser LispVal
parseString = do
  _ <- char '"'
  x <- many (noneOf "\"")
  _ <- char '"'
  return $ String x

parseNumber :: Parser LispVal
parseNumber = do
  d <- many1 digit
  return $ (Number . read) d

parseAtom :: Parser LispVal
parseAtom = do
  first <- letter <|> symbol
  rest <- many (letter <|> digit <|> symbol)
  let atom = first:rest
  return $ case atom of
            "#t" -> Bool True
            "#f" -> Bool False
            _    -> Atom atom

parseList :: Parser LispVal
parseList = liftM List $ sepEndBy parseExpr spaces

parseDottedList :: Parser LispVal
parseDottedList = do
    h <- endBy parseExpr spaces
    t <- char '.' >> spaces >> parseExpr
    return $ DottedList h t

parseQuoted :: Parser LispVal
parseQuoted = do
    _ <- char '\''
    x <- parseExpr
    return $ List [Atom "quote", x]

parseExpr :: Parser LispVal
parseExpr = parseAtom
         <|> parseString
         <|> parseNumber
         <|> parseQuoted
         <|> do
           _ <- char '('
           _ <- many spaces
           x <- try parseList <|> parseDottedList
           _ <- many spaces
           _ <- char ')'
           return x

readExpr :: String -> LispVal
readExpr input = case parse parseExpr "lisp" input of
    Left err -> String $ "No match: " ++ show err
    Right x -> x

-- Evaluator
-- Primitives, implemented in terms of haskell
primitives :: [(String, [LispVal] -> LispVal)]
primitives = [("*", numericBinop (*)),
              ("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("/", numericBinop div),
              ("/=", numBoolBinop (/=)),
              ("<", numBoolBinop (<)),
              ("<=", numBoolBinop (<=)),
              ("=", numBoolBinop (==)),
              (">", numBoolBinop (>)),
              (">=", numBoolBinop (>=)),
              ("mod", numericBinop mod),
              ("quot", numericBinop quot),
              ("quote", head),
              ("rem", numericBinop rem)]

-- Helpers for the evaluator
apply :: String -> [LispVal] -> LispVal
apply func args = maybe (error err) ($ args) $ lookup func primitives where
  err = "Undefined function " ++ show func

-- `numericBinop` takes a primitive Haskell function and wraps it with code to
-- unpack an argument list, apply the function to it, and wrap the result up in
-- LispVal Number constructor
numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> LispVal
numericBinop op params = Number $ foldl1 op $ map unpackNum params

numBoolBinop :: (Integer -> Integer -> Bool) -> [LispVal] -> LispVal
numBoolBinop op [Number one, Number two] = Bool (one `op` two)
numBoolBinop _ _  = error "Unexpected arguments to numeric binary operator"

-- Evaluation rules
eval :: LispVal -> LispVal
eval val@(String _) = val
eval val@(Number _) = val
eval val@(Bool _) = val
eval (List [Atom "quote", val]) = val
eval (List (Atom func : args)) = apply func $ map eval args -- Is this lazy??

-- REPL helpers
flushStr :: String -> IO ()
flushStr str = putStr str >> hFlush stdout

readPrompt :: String -> IO String
readPrompt prompt = flushStr prompt >> getLine

evalString = eval . readExpr

evalAndPrint :: String -> IO ()
evalAndPrint expr = print (evalString expr)

until_ :: Monad m => (a -> Bool) -> m a -> (a -> m ()) -> m ()
until_ pred prompt action = do
   input <- prompt
   unless (pred input) $ action input >> until_ pred prompt action

runRepl :: IO ()
runRepl = until_ (== "q") (readPrompt "λ> ") evalAndPrint

-- Main
main :: IO ()
main = do args <- getArgs
          case length args of
              0 -> runRepl
              1 -> evalAndPrint $ head args
              otherwise -> putStrLn "Program takes only 0 or 1 argument"
