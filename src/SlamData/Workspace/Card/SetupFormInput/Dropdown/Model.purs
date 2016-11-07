module SlamData.Workspace.Card.SetupFormInput.Dropdown.Model where

import SlamData.Prelude

import Data.Argonaut (JCursor, Json, decodeJson, (~>), (:=), (.?), jsonEmptyObject, isNull, jsonNull)
import Data.Foldable as F

import SlamData.Common.Align (Align)

import Test.StrongCheck.Arbitrary (arbitrary)
import Test.StrongCheck.Gen as Gen
import Test.Property.ArbJson (runArbJCursor)

type DropdownR =
  { name ∷ Maybe JCursor
  , value ∷ JCursor
  , label ∷ Maybe JCursor
  , verticalAlign ∷ Align
  , horizontalAlign ∷ Align
  }

type Model = Maybe DropdownR

initialModel ∷ Model
initialModel = Nothing

eqDropdownR ∷ DropdownR → DropdownR → Boolean
eqDropdownR r1 r2 =
  F.and
    [ r1.name ≡ r2.name
    , r1.value ≡ r2.value
    , r1.label ≡ r2.label
    , r1.verticalAlign ≡ r2.verticalAlign
    , r1.horizontalAlign ≡ r2.horizontalAlign
    ]

eqModel ∷ Model → Model → Boolean
eqModel Nothing Nothing = true
eqModel (Just r1) (Just r2) = eqDropdownR r1 r2
eqModel _ _ = false

genModel ∷ Gen.Gen Model
genModel = do
  isNothing ← arbitrary
  if isNothing
    then pure Nothing
    else map Just do
    name ← map (map runArbJCursor) arbitrary
    value ← map runArbJCursor arbitrary
    label ← map (map runArbJCursor) arbitrary
    verticalAlign ← arbitrary
    horizontalAlign ← arbitrary
    pure { name
         , value
         , label
         , verticalAlign
         , horizontalAlign
         }

encode ∷ Model → Json
encode Nothing = jsonNull
encode (Just r) =
  "formInputType" := "dropdown"
  ~> "name" := r.name
  ~> "value" := r.value
  ~> "label" := r.label
  ~> "verticalAlign" := r.verticalAlign
  ~> "horizontalAlign" :=  r.horizontalAlign
  ~> jsonEmptyObject

decode ∷ Json → String ⊹ Model
decode js
  | isNull js = pure Nothing
  | otherwise = map Just do
    obj ← decodeJson js
    fiType ← obj .? "formInputType"
    unless (fiType ≡ "dropdown")
      $ throwError "This is not dropdown form input setup"
    name ← obj .? "name"
    value ← obj .? "value"
    label ← obj .? "label"
    horizontalAlign ← obj .? "horizontalAlign"
    verticalAlign ← obj .? "verticalAlign"
    pure { name
         , value
         , label
         , horizontalAlign
         , verticalAlign
         }
