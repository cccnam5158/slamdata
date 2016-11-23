{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Workspace.Card.Eval.Common where

import SlamData.Prelude

import Control.Monad.Aff.Free (class Affable)
import Control.Monad.Throw (class MonadThrow, throw)

import Data.Path.Pathy as Path

import Quasar.Types (FilePath)

import SlamData.Effects (SlamDataEffects)
import Quasar.Advanced.QuasarAF as QF
import SlamData.Quasar.Error as QE
import SlamData.Quasar.Class (class QuasarDSL, class ParQuasarDSL, sequenceQuasar)
import SlamData.Workspace.Card.Eval.Monad as CEM

validateResources
  ∷ ∀ m t
  . ( Affable SlamDataEffects m
    , MonadThrow CEM.CardError m
    , QuasarDSL m
    , ParQuasarDSL m
    , Traversable t
    )
  ⇒ t FilePath
  → m Unit
validateResources fs = do
  res ← sequenceQuasar (map (\path → Tuple path <$> QF.fileMetadata path) fs)
  for_ res case _ of
    path × Left reason →
      throw $ QE.prefixMessage ("Resource `" ⊕ Path.printPath path ⊕ "` is unavailable") reason
    _ →
      pure unit
