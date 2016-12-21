module SlamData.Workspace.Card.SetupFormInput.Static.Model where

import SlamData.Prelude

import Data.Argonaut (JCursor, Json, decodeJson, (~>), (:=), (.?), jsonEmptyObject, isNull, jsonNull)
import Data.Foldable as F

import Test.StrongCheck.Arbitrary (arbitrary)
import Test.StrongCheck.Gen as Gen
import Test.StrongCheck.Data.Argonaut (runArbJCursor)

type StaticR =
  { value ∷ JCursor
  }

type Model = Maybe StaticR

initialModel ∷ Model
initialModel = Nothing

eqR ∷ StaticR → StaticR → Boolean
eqR r1 r2 =
  F.and
    [ r1.value ≡ r2.value
    ]

eqModel ∷ Model → Model → Boolean
eqModel Nothing Nothing = true
eqModel (Just r1) (Just r2) = eqR r1 r2
eqModel _ _ = false

genModel ∷ Gen.Gen Model
genModel = do
  isNothing ← arbitrary
  if isNothing
    then pure Nothing
    else map Just do
    value ← map runArbJCursor arbitrary
    pure { value
         }

encode ∷ Model → Json
encode Nothing = jsonNull
encode (Just r) =
  "formInputType" := "static"
  ~> "value" := r.value
  ~> jsonEmptyObject

decode ∷ Json → String ⊹ Model
decode js
  | isNull js = pure Nothing
  | otherwise = map Just do
    obj ← decodeJson js
    fiType ← obj .? "formInputType"
    unless (fiType ≡ "static")
      $ throwError "This is not text form input setup"
    value ← obj .? "value"
    pure { value
         }
