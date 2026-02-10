# `RequirePackageImports` plugin

[![Hackage Version](https://img.shields.io/hackage/v/require-package-imports)](https://hackage.haskell.org/package/require-package-imports)
[![Packaging status](https://repology.org/badge/tiny-repos/haskell:require-package-imports.svg)](https://repology.org/project/haskell:require-package-imports/versions)
[![latest packaged versions](https://repology.org/badge/latest-versions/haskell:require-package-imports.svg)](https://repology.org/project/haskell:require-package-imports/versions)

Require [package-qualified imports](https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/package_qualified_imports.html)

A GHC plugin to ensure package-qualified imports are used.

## motivation

Package-qualified imports solve a few problems. First, they communicate provenance to a reader. It’s not always obvious where particular modules come from. Second, the eliminate ambiguity – if multiple packages expose the same module name, this makes it clear which one is being used. Third, it improves alignment – for example, [the Extra package](https://hackage.haskell.org/package/extra) could expose `Data.List` and then both can be imported side-by-side[^1].

```haskell
import "base" Data.List (break)
import "extra" Data.List (trim, (!?))
```

[^1]: I _think_ there is a version of GHC before which multiple imports of the same module name doesn’t work, but I don’t recall which version.

Finally, it reduces duplication. Many packages introduce the package name _somewhere_ in the module hierarchy (Extra does it at the end, Megaparsec does it after `Text`[^2], etc). This redundancy is unnecessary, because we already have a tool for this (since GHC 6.10!)

[^2]: Should all of Megaparsec even _be_ under `Text`? I feel like the clumping of its modules is due to that module naming decision.

This pattern is also seen in other programming languages (which you may have varying opinions on):

- Rust’s [`use some_crate::some_mod;` syntax](https://doc.rust-lang.org/std/keyword.use.html)
- Python’s [import packages](https://docs.python.org/3/reference/import.html#searching)

## usage

Add the following to your Cabal stanzas, and start getting errors around missing package-qualifiers on your imports.

```cabal
  build-depends: require-package-imports ^>= 0.1.0
  ghc-options:
    -fplugin RequirePackageImports
```

This also implies the `PackageImports` extension, so it doesn’t need to be enabled explicitly.

## versioning

This project largely follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/) (PVP), but is more strict in some ways.

The version always has four components, `A.B.C.D`. The first three correspond to those required by PVP, while the fourth matches the “patch” component from [Semantic Versioning](https://semver.org/).

Here is a breakdown of some of the constraints:

### sensitivity to additions to the API

PVP recommends that clients follow [these import guidelines](https://wiki.haskell.org/Import_modules_properly) in order that they may be considered insensitive to additions to the API. However, this isn’t sufficient. We expect clients to follow these additional recommendations for API insensitivity

If you don’t follow these recommendations (in addition to the ones made by PVP), you should ensure your dependencies don’t allow a range of `C` values. That is, your dependencies should look like

```cabal
yaya >=1.2.3 && <1.2.4
```

rather than

```cabal
yaya >=1.2.3 && <1.3
```

#### use package-qualified imports everywhere

If your imports are [package-qualified](https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/package_qualified_imports.html?highlight=packageimports#extension-PackageImports), then a dependency adding new modules can’t cause a conflict with modules you already import.

#### avoid orphans

Because of the transitivity of instances, orphans make you sensitive to your dependencies’ instances. If you have an orphan instance, you are sensitive to the APIs of the packages that define the class and the types of the instance.

One way to minimize this sensitivity is to have a separate package (or packages) dedicated to any orphans you have. Those packages can be sensitive to their dependencies’ APIs, while the primary package remains insensitive, relying on the tighter ranges of the orphan packages to constrain the solver.

### transitively breaking changes (increments `A`)

#### removing a type class instance

Type class instances are imported transitively, and thus changing them can impact packages that only have your package as a transitive dependency.

#### widening a dependency range with new major versions

This is a consequence of instances being transitively imported. A new major version of a dependency can remove instances, and that can break downstream clients that unwittingly depended on those instances.

A library _may_ declare that it always bumps the `A` component when it removes an instance (as this policy dictates). In that case, only `A` widenings need to induce `A` bumps. `B` widenings can be `D` bumps like other widenings, Alternatively, one may compare the APIs when widening a dependency range, and if no instances have been removed, make it a `D` bump.

### breaking changes (increments `B`)

#### restricting an existing dependency’s version range in any way

Consumers have to contend not only with our version bounds, but also with those of other libraries. It’s possible that some dependency overlapped in a very narrow way, and even just restricting a particular patch version of a dependency could make it impossible to find a dependency solution.

#### restricting the license in any way

Making a license more restrictive may prevent clients from being able to continue using the package.

#### adding a dependency

A new dependency may make it impossible to find a solution in the face of other packages dependency ranges.

### non-breaking changes (increments `C`)

#### adding a module

This is also what PVP recommends. However, unlike in PVP, this is because we recommend that package-qualified imports be used on all imports.

### other changes (increments `D`)

#### widening a dependency range for non-major versions

This is fairly uncommon, in the face of `^>=`-style ranges, but it can happen in a few situations.

#### deprecation

**NB**: This case is _weaker_ than PVP, which indicates that packages should bump their major version when adding `deprecation` pragmas.

We disagree with this because packages shouldn’t be _publishing_ with `-Werror`. The intent of deprecation is to indicate that some API _will_ change. To make that signal a major change itself defeats the purpose. You want people to start seeing that warning as soon as possible. The major change occurs when you actually remove the old API.

Yes, in development, `-Werror` is often (and should be) used. However, that just helps developers be aware of deprecations more immediately. They can always add `-Wwarn=deprecation` in some scope if they need to avoid updating it for the time being.

## licensing

This package is licensed under [The GNU AGPL 3.0 only](./LICENSE). If you need a license for usage that isn’t covered under the AGPL, please contact [Greg Pfeil](mailto:greg@technomadic.org?subject=licensing%20require-package-imports).

You should review the [license report](docs/license-report.md) for details about dependency licenses.

## comparisons

Other projects similar to this one, and how they differ.
