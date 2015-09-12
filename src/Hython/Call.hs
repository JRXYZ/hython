module Hython.Call (call)
where

import Control.Arrow (first)
import Control.Monad (forM_, when, zipWithM)
import Control.Monad.Cont (callCC)
import Control.Monad.Cont.Class (MonadCont)
import Control.Monad.IO.Class (MonadIO)
import Data.Text (pack)
import Safe (atDef)

import Hython.Builtins (callBuiltin, getAttr)
import Hython.Types

call :: (MonadCont m, MonadInterpreter m, MonadIO m) => Object -> [Object] -> [(String, Object)] -> m Object
call (BuiltinFn name) args _ = callBuiltin name args

call (Class info) args kwargs = do
    obj <- newObject info

    mconstructor <- getAttr "__init__" obj
    _ <- case mconstructor of
        Just ctor   -> call ctor args kwargs
        Nothing     -> return None

    return obj

call (Function fnName params statements) args kwargs = do
    requiredParams <- pure $ takeWhile isRequiredParam params
    when (length args < length requiredParams) $
        raise "TypeError" ("not enough arguments passed to '" ++ fnName ++ "'")
    when (length requiredParams == length params && length args > length requiredParams) $
        raise "TypeError" ("too many args passed to '" ++ fnName ++ "'")

    result <- callCC $ \returnCont -> do
        pushEnvFrame
        bindings <- zipWithM getArg params [0..]
        forM_ bindings $ \(name, obj) ->
            bind (pack name) obj

        pushControlCont ReturnCont returnCont

        evalBlock statements
        return None

    _ <- popEnvFrame
    popControlCont ReturnCont

    return result

  where
    getArg (NamedParam name) i = return (name, args !! i)
    getArg (DefParam name obj) i = return (name, atDef obj args i)
    getArg (SParam name) i = do
        tuple <- newTuple (drop i args)
        return (name, tuple)
    getArg (DSParam name) _ = do
        dict <- newDict $ map (first String) kwargs
        return (name, dict)

    isRequiredParam (NamedParam _) = True
    isRequiredParam _ = False

call (Method name receiver params statements) args kwargs =
    case receiver of
        ClassBinding _ cls      -> call (Function name params statements) (cls:args) kwargs
        InstanceBinding _ obj   -> call (Function name params statements) (obj:args) kwargs

call _ _ _ = do
    raise "TypeError" "object is not callable"
    return None

