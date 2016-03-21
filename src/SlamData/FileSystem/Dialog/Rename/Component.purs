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

module SlamData.FileSystem.Dialog.Rename.Component where

import SlamData.Prelude

import Control.Monad.Aff (attempt)
import Control.Monad.Eff.Exception (message)
import Control.Monad.Error.Class (throwError)
import Control.UI.Browser (reload)

import Data.Array (elemIndex, singleton, sort, nub)
import Data.Lens ((^.), (%~), (.~), (?~), lens, LensP)
import Data.Path.Pathy (printPath, parseAbsDir, sandbox, rootDir, (</>))
import Data.String as S

import Halogen as H
import Halogen.CustomProps as Cp
import Halogen.HTML.Events.Handler as HEH
import Halogen.HTML.Events.Indexed as HE
import Halogen.HTML.Indexed as HH
import Halogen.HTML.Properties.Indexed as HP
import Halogen.HTML.Properties.Indexed.ARIA as ARIA
import Halogen.Themes.Bootstrap3 as B

import Quasar.Aff as API
import Quasar.Auth as Auth

import SlamData.Config as Config
import SlamData.Effects (Slam)
import SlamData.Dialog.Render (modalDialog, modalHeader, modalBody, modalFooter)
import SlamData.FileSystem.Resource as R
import SlamData.Render.Common (fadeWhen, formGroup)
import SlamData.Render.CSS as Rc

import Utils.Path (DirPath, dropNotebookExt)

type State =
  { showList :: Boolean
  , initial :: R.Resource
  , name :: String
  , dirs :: Array R.Resource
  , dir :: DirPath
  , siblings :: Array R.Resource
  , error :: Maybe String
  }

initialState :: R.Resource -> State
initialState resource =
  { showList: false
  , initial: resource
  , name: if R.isNotebook resource
          then dropNotebookExt $ R.resourceName resource
          else R.resourceName resource
  , dir: R.resourceDir resource
  , siblings: mempty
  , dirs: singleton R.root
  , error: Nothing
  }

_showList :: LensP State Boolean
_showList = lens _.showList (_ { showList = _ })

_initial :: LensP State R.Resource
_initial = lens _.initial (_ { initial = _ })

_name :: LensP State String
_name = lens _.name (_ { name = _ })

_dirs :: LensP State (Array R.Resource)
_dirs = lens _.dirs (_ { dirs = _ })

_dir :: LensP State DirPath
_dir = lens _.dir (_ { dir = _ })

_siblings :: LensP State (Array R.Resource)
_siblings = lens _.siblings (_ { siblings = _ })

_error :: LensP State (Maybe String)
_error = lens _.error (_ { error = _ })

renameSlam :: State -> R.Resource
renameSlam r =
  let initial = r.initial
      name = r.name
      nameWithExt = if R.isNotebook initial
                    then name <> "." <> Config.notebookExtension
                    else name
  in initial # (R._name .~ nameWithExt)
           <<< (R._root .~ r.dir)

validate :: State -> State
validate r
  | r.initial == renameSlam r = r # _error .~ Nothing
  | otherwise = r # _error .~ either Just (const Nothing) do
    let name = r.name
    when (name == "")
      $ throwError "Please enter a name for the file"

    when (isJust $ S.stripSuffix ("." <> Config.notebookExtension) name)
      $ throwError $ "Please choose an alternative name, ."
      <> Config.notebookExtension
      <> " is a reserved extension"

    when (isJust $ S.indexOf "/" name)
      $ throwError "Please entera valid name for the file"

    let nameWithExt = if R.isNotebook (r.initial)
                      then name <> "." <> Config.notebookExtension
                      else name
    when (isJust $ elemIndex nameWithExt (map (_ ^. R._name) (r.siblings)))
      $ throwError "An item with this name already exists in the target folder"

data Query a
  = Dismiss a
  | SetShowList Boolean a
  | ToggleShowList a
  | Submit a
  | NameTyped String a
  | DirTyped String a
  | DirClicked R.Resource a
  | SetSiblings (Array R.Resource) a
  | AddDirs (Array R.Resource) a
  | Init a

type DSL = H.ComponentDSL State Query Slam
type HTML = H.ComponentHTML Query

comp :: H.Component State Query Slam
comp =
  H.lifecycleComponent
    { render
    , eval
    , initializer: Just (H.action Init)
    , finalizer: Nothing
    }

render :: State -> HTML
render dialog =
  modalDialog
  [ modalHeader "Move/rename"
  , modalBody
    $ HH.form
        [ HP.classes [ Rc.renameDialogForm ]
        , Cp.nonSubmit
        , HE.onClick (\_ -> HEH.stopPropagation $> H.action (SetShowList false))
        ]
        [ nameInput
        , dirDropdownField
        , dirDropdownList
        , errorMessage
        ]
  , modalFooter
      [ HH.button
          [ HP.classes [ B.btn ]
          , HE.onClick (HE.input_ Dismiss)
          ]
          [ HH.text "Cancel" ]
      , HH.button
          [ HP.classes [ B.btn, B.btnPrimary ]
          , HP.disabled $ isJust $ dialog.error
          , HE.onClick (HE.input_ Submit)
          ]
          [ HH.text "Rename" ]
      ]
  ]
  where
  nameInput :: HTML
  nameInput =
    formGroup [ HH.input [ HP.classes [ B.formControl ]
                        , HP.value (dialog.name)
                        , HP.placeholder "New name"
                        , HE.onValueInput (HE.input NameTyped)
                        ]
              ]

  dirDropdownField :: HTML
  dirDropdownField =
    HH.div
      [ HP.classes [ B.inputGroup ] ]
      [ HH.input
          [ HP.classes [ B.formControl ]
          , HP.placeholder "New directory"
          , HE.onValueInput (HE.input DirTyped)
          , HP.value (printPath $ dialog ^. _dir)
          ]
      , HH.span
          [ HP.classes [ B.inputGroupBtn ] ]
          [ HH.button
              [ HP.classes [ B.btn, B.btnDefault ]
              , HE.onClick \_ -> HEH.stopPropagation $> H.action ToggleShowList
              , ARIA.label "Select a destination folder"
              , HP.title "Select a destination folder"
              ]
              [ HH.span [ HP.classes [ B.caret ] ] [ ] ]
          ]
      ]
  dirDropdownList :: HTML
  dirDropdownList =
    HH.ul [ HP.classes $ [ B.listGroup, Rc.fileListGroup ]
           <> fadeWhen (not $ dialog.showList) ]
    $ renameItem <$> dialog.dirs

  errorMessage :: HTML
  errorMessage =
    HH.div [ HP.classes $ [ B.alert, B.alertDanger ]
            <> fadeWhen (isNothing (dialog.error)) ]
    $ maybe [ ] (pure <<< HH.text) (dialog.error)

  renameItem :: R.Resource -> HTML
  renameItem res =
    HH.button [ HP.classes ([ B.listGroupItem ]
                          <> (if R.isHidden res
                              then [ Rc.itemHidden ]
                              else [ ]))
             , HE.onClick (HE.input_ (DirClicked res))
             ]
    [ HH.text (R.resourcePath res) ]

eval :: Natural Query DSL
eval (Dismiss next) = pure next
eval (SetShowList bool next) = do
  H.modify (_showList .~ bool)
  H.modify validate
  pure next
eval (ToggleShowList next) = do
  H.modify (_showList %~ not)
  H.modify validate
  pure next
eval (Submit next) = do
  state <- H.get
  let src = state.initial
      tgt = R.getPath $ renameSlam state
  result <- H.fromAff $ attempt $ Auth.authed $ API.move src tgt
  case result of
    Left e ->
      H.modify (_error ?~ message e)
    Right _ -> do
      H.modify (_error .~ Nothing)
      H.fromEff reload
  pure next
eval (NameTyped str next) = do
  H.modify (_name .~ str)
  H.modify validate
  pure next
eval (DirTyped str next) = do
  maybe (pure unit) (dirItemClicked <<< R.mkDirectory <<< Right) do
    d <- parseAbsDir str
    s <- sandbox rootDir d
    pure $ rootDir </> s
  pure next
eval (DirClicked res next) = do
  dirItemClicked res
  pure next
eval (SetSiblings ss next) = do
  H.modify (_siblings .~ ss)
  pure next
eval (AddDirs ds next) = do
  H.modify (_dirs %~ append ds >>> nub >>> sort)
  pure next
eval (Init next) = do
  state <- H.get
  dirItemClicked $ R.parent $ state.initial
  pure next

dirItemClicked :: R.Resource -> DSL Unit
dirItemClicked res =
  case R.getPath res of
    Left _ -> pure unit
    Right dir -> do
      siblings <- H.fromAff $ Auth.authed $ API.children dir
      H.modify
        $ (_dir .~ dir)
        <<< (_showList .~ false)
        <<< (_siblings .~ siblings)
