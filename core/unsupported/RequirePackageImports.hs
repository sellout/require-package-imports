{-# LANGUAGE CPP #-}
{-# LANGUAGE Trustworthy #-}

-- |
-- Copyright: 2026 Greg Pfeil
-- License: AGPL-3.0-only WITH Universal-FOSS-exception-1.0 OR LicenseRef-commercial
--
-- A no-op version of the "RequirePackageImports" plugin to load on GHC’s that
-- the actual plugin doesn’t yet compile on. This prevents users from having to
-- conditionalize their use of the plugin.
--
-- __NB__: This module must compile for GHC 7.2 (the first version that
--         introduces plugins) through the version before the “supported”
--         "RequirePackageImports" module (which is currently GHC 9.6).
module RequirePackageImports
  ( plugin,
  )
where

import safe "base" Data.Function (($))
import safe "base" Data.Functor ((<$))
import safe "base" Data.List (intercalate)
import safe "base" Data.Monoid ((<>))
import safe "base" Data.String (String)
import safe "base" Data.Version (Version, makeVersion, showVersion)
import safe "base" System.IO (putStr)
#if MIN_VERSION_ghc(9, 0, 1)
import qualified "ghc" GHC.Plugins as Plugins
#else
import qualified "ghc" GhcPlugins as Plugins
#endif

-- | What to print before a diagnostic message to make a plugin report look like
--   other GHC reports. The parameters are structured so that it can be
--   partially applied with the module at the top-level, and then the
--   `Plugins.CommandLineOption`s at each phase, and finally the prefix for each
--   diagnostic.
--
--  __TODO__: This should be in ghc-plugin-utils.
errorPrelude ::
  -- | The name of the module that defines the @plugin@ entry-point.
  String ->
  -- | The options passed to a particular plugin phase.
  [Plugins.CommandLineOption] ->
  -- | The severity of the diagnostic. Generally “warning”, “error”, or “info”.
  String ->
  String
errorPrelude pluginModule optStrs prefix =
  "on the commandline: "
    <> prefix
    <> ": ["
    <> pluginModule
    <> " plugin] ["
    <> intercalate ", " optStrs
    <> "]\n    "

-- | This is a plugin that does nothing but report that it’s doing nothing. This
--   is a fallback for plugins where we want to avoid making users
--   conditionalize the use of the plugin.
--
--  __NB__: Where possible (GHC 8.6+), this plugin won’t trigger recompilation.
--
--  __TODO__: This should be in ghc-plugin-utils.
nopPlugin ::
  -- | The module name of the plugin.
  String ->
  Version ->
  Plugins.Plugin
nopPlugin pluginModule minSupportedGhcVersion =
  Plugins.defaultPlugin
    { Plugins.installCoreToDos = \optStrs ->
        ( <$
            Plugins.liftIO
              ( putStr $
                  errorPrelude pluginModule optStrs "info"
                    <> "This plugin has no effect prior to GHC "
                    <> showVersion minSupportedGhcVersion
                    <> ", so ensure it’s being tested\n    on a newer release."
              )
        )
    }
#if MIN_VERSION_ghc(8, 6, 1)
    { Plugins.pluginRecompile = Plugins.purePlugin
    }
#endif

-- | The entry-point for the GHC plugin. This is used by passing
--   [@-fplugin=RequirePackageImports@](https://downloads.haskell.org/ghc/latest/docs/users_guide/extending_ghc.html#ghc-flag-fplugin-module)
--   to GHC.
--
--  __NB__: This plugin has no effect prior to GHC 9.6.
plugin :: Plugins.Plugin
plugin = nopPlugin "RequirePackageImports" $ makeVersion [9, 6, 1]
