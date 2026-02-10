{-# LANGUAGE CPP #-}
{-# LANGUAGE Trustworthy #-}
#if MIN_VERSION_GLASGOW_HASKELL(9, 10, 1, 0)
-- FIXME: This shouldn’t be the case, figure out why it’s incomplete.
{-# OPTIONS_GHC -Wno-incomplete-record-selectors #-}
#endif

-- |
-- Copyright: 2026 Greg Pfeil
-- License: AGPL-3.0-only WITH Universal-FOSS-exception-1.0 OR LicenseRef-commercial
--
-- This plugin ensures that all imports include a package-qualifier.
--
-- __TODO__: Add support for whitelisting module names. Sometimes the same
--           module comes from different packages with different dependency
--           versions, and it’s easier to drop the qualification requirement in
--           that case than to add CPP.
module RequirePackageImports
  ( plugin,

    -- * components
    dflagsPlugin,
    parsedResultAction,
  )
where

import safe "base" Control.Applicative (pure)
import safe "base" Control.Category ((.))
import safe "base" Data.Foldable (foldr)
import safe "base" Data.Function (const, flip, ($))
import safe "base" Data.Functor (fmap)
import safe "base" Data.Maybe (Maybe (Nothing))
import safe "base" Data.String (String, fromString)
import safe "base" System.IO (IO)
import qualified "ghc" GHC.Driver.Errors.Types as Errors
import qualified "ghc" GHC.Hs as Hs
import qualified "ghc" GHC.Hs.Extension as HsExt
import qualified "ghc" GHC.Parser.Annotation as Annotation
import "ghc" GHC.Plugins (Plugin, defaultPlugin)
import qualified "ghc" GHC.Plugins as Plugins
import qualified "ghc" GHC.Types.Error as Error
import qualified "ghc" GHC.Types.SourceText as SourceText
import qualified "ghc" Language.Haskell.Syntax as Syntax
import safe qualified "ghc-boot-th" GHC.LanguageExtensions.Type as Extension

mkStringLit :: String -> SourceText.StringLiteral
mkStringLit =
  flip (SourceText.StringLiteral SourceText.NoSourceText) Nothing . fromString

reportNoPkgQual ::
  Syntax.LImportDecl HsExt.GhcPs -> Maybe (Error.MsgEnvelope Errors.GhcMessage)
reportNoPkgQual imp = case Syntax.ideclPkgQual $ Plugins.unLoc imp of
  Plugins.NoRawPkgQual ->
    -- FIXME: Why do I need to use this twice?
    let reason = Error.WarningWithoutFlag
     in pure
          Error.MsgEnvelope
            { Error.errMsgSpan = Annotation.getLocA imp,
              Error.errMsgContext = Plugins.alwaysQualify,
              Error.errMsgDiagnostic =
                Errors.GhcUnknownMessage
                  . Error.UnknownDiagnostic (const Error.defaultOpts)
                  . Error.mkPlainDiagnostic
                    reason
                    [ Error.UnknownHint
                        (Plugins.unLoc imp)
                          { Syntax.ideclPkgQual =
                              Plugins.RawPkgQual $ mkStringLit "<package name>"
                          }
                    ]
                  $ fromString "Missing package-qualified import. (Required due to use of ‘-fplugin RequirePackageImports’)",
              -- TODO: Make severity configurable.
              Error.errMsgSeverity = Error.SevError,
              Error.errMsgReason = Error.ResolvedDiagnosticReason reason
            }
  Plugins.RawPkgQual _ -> Nothing

processImports ::
  Error.Messages Errors.GhcMessage ->
  [Syntax.LImportDecl HsExt.GhcPs] ->
  IO (Error.Messages Errors.GhcMessage)
processImports msgs =
  -- TODO: For each import missing its qualifier, we create an error message. It
  --       should include a hint for each potential package. I don’t know how
  --       easy it is to find the potential packages – if we push this to a
  --       later phase, the import may already be resolved, but at that point,
  --       ambiguous packages probably produced a _different_ error, without the
  --       hint we want (or maybe GHC already hints in that case, in which case,
  --       we can skip). `ImportSuggestion` may give use the hint we want.
  pure . foldr (flip (foldr Error.addMessage) . reportNoPkgQual) msgs

-- | Enables `Extension.PackageImports`, so one can address the plugin’s reports.
--
-- @since 0.0.1.0
dflagsPlugin ::
  [Plugins.CommandLineOption] -> Plugins.DynFlags -> IO Plugins.DynFlags
dflagsPlugin _ = pure . (`Plugins.xopt_set` Extension.PackageImports)

-- | Produce `Diagnostic`s for any imports that are missing package qualifiers.
--
-- @since 0.0.1.0
parsedResultAction ::
  [Plugins.CommandLineOption] ->
  Plugins.ModSummary ->
  Plugins.ParsedResult ->
  Plugins.Hsc Plugins.ParsedResult
parsedResultAction _ _ parsed = Plugins.Hsc $ \_ msgs ->
  fmap (parsed,)
    . processImports msgs
    . Syntax.hsmodImports
    . Plugins.unLoc
    . Hs.hpm_module
    $ Plugins.parsedResultModule parsed

-- |
--
--  __TODO__: This should be in ghc-plugin-utils.
liftDflagsPlugin ::
  ([Plugins.CommandLineOption] -> Plugins.DynFlags -> IO Plugins.DynFlags) ->
  [Plugins.CommandLineOption] ->
  Plugins.HscEnv ->
  IO Plugins.HscEnv
liftDflagsPlugin dPlugin opts env =
  fmap (\hsc_dflags -> env {Plugins.hsc_dflags}) . dPlugin opts $
    Plugins.hsc_dflags env

-- | The plugin entry point. This is used by passing @-fplugin
--   RequirePackageImports@ to GHC.
--
-- @since 0.0.1.0
plugin :: Plugin
plugin =
  defaultPlugin
    { Plugins.pluginRecompile = Plugins.flagRecompile,
      Plugins.parsedResultAction = \_ _ parsed -> Plugins.Hsc $ \_ msgs ->
        fmap (parsed,)
          . processImports msgs
          . Syntax.hsmodImports
          . Plugins.unLoc
          . Hs.hpm_module
          $ Plugins.parsedResultModule parsed
    }
#if MIN_VERSION_ghc(9, 2, 1)
    { Plugins.driverPlugin = liftDflagsPlugin dflagsPlugin
    }
#else
    { Plugins.dflagsPlugin = dflagsPlugin
    }
#endif
