module Hython.Module (loadModule)
where

import Control.Monad.State
import Data.List
import System.FilePath.Posix

import Language.Python.Core

import qualified Hython.AttributeDict as AttributeDict
import Hython.Environment
import Hython.InterpreterState

loadModule :: String -> (String -> AttributeDict -> Interpreter ()) -> Interpreter Module
loadModule importPath action = do
    current         <- gets currentModule
    loadedModules   <- gets modules

    let resolvedPath = resolveModulePath importPath (modulePath current)

    case lookupModuleByPath resolvedPath loadedModules of
        Just m  -> return m
        Nothing -> do
            code <- liftIO $ readFile resolvedPath
            dict <- liftIO AttributeDict.empty

            let newModule = Module {
                moduleName = newModuleName,
                modulePath = resolvedPath,
                moduleDict = dict
            }

            scope <- currentScope

            modify $ \s -> s { currentModule = newModule }
            updateScope $ scope { moduleScope = dict }

            action code dict

            updateScope $ scope { moduleScope = moduleScope scope }
            modify $ \s -> s { currentModule = current, modules = newModule : modules s }

            return newModule
  where
    lookupModuleByPath resolvedPath = find (\m -> modulePath m == resolvedPath)
    newModuleName = takeBaseName importPath

resolveModulePath :: String -> FilePath -> FilePath
resolveModulePath path currentModulePath = currentModuleDir `combine` name
  where
    currentModuleDir = takeDirectory currentModulePath
    name = takeBaseName path ++ ".py"
