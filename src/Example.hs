{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecordWildCards #-}
module Main where

import           Control.Monad
import           Data.Bool
import           Data.Monoid
import qualified Data.Text         as T
import           GHCJS.DOM.Event
import           GHCJS.DOM.HTMLInputElement
import           GHCJS.DOM.UIEvent

import           Miso

data Model = Model
  { entries :: [Entry]
  , field :: String
  , uid :: Int
  , visibility :: String
  , start :: Bool
  } deriving (Show, Eq)

data Entry = Entry
  { description :: String
  , completed :: Bool
  , editing :: Bool
  , eid :: Int
  } deriving (Show, Eq)

emptyModel :: Model
emptyModel = Model
  { entries = []
  , visibility = "All"
  , field = mempty
  , uid = 0
  , start = False
  }

newEntry :: String -> Int -> Entry
newEntry desc eid = Entry
  { description = desc
  , completed = False
  , editing = False
  , eid = eid
  }

data Msg
  = Start
  | UpdateField String
  | EditingEntry Int Bool
  | UpdateEntry Int String
  | Add
  | Delete Int
  | DeleteComplete
  | Check Int Bool
  | CheckAll Bool
  | ChangeVisibility String
   deriving Show

main :: IO ()
main = do
  putStrLn "hi"
  (sig, send) <- signal Start
  runSignal ["keydown", "click", "change", "input", "blur", "dblclick"] $
    view send <$> foldp update emptyModel sig


update :: Msg -> Model -> Model
update Start model = model { start = True }
update Add model@Model{..} = 
  model { 
    uid = uid + 1
  , field = mempty
  , entries = 
      if null field
        then entries
        else entries ++ [ newEntry field uid ]
  }
update (UpdateField str) model = model { field = str }
update (EditingEntry id' isEditing) model@Model{..} = 
  model { entries = newEntries }
    where
      newEntries = [ t { editing = isEditing }
                   | t <- entries, eid t == id'
                   ]
update (UpdateEntry id' task) model@Model{..} =
  model { entries = newEntries }
    where
      newEntries = [ t { description = task }
                   | t <- entries, eid t == id' 
                   ]
update (Delete id') model@Model{..} =
  model { entries = filter (\t -> eid t /= id') entries }

update DeleteComplete model@Model{..} =
  model { entries = filter (not . completed) entries }

update (Check id' isCompleted) model@Model{..} =
  model { entries = newEntries }
    where
      newEntries =
        flip map entries $ \t ->
          case eid t == id' of
            True -> t { completed = isCompleted }
            False -> t 

update (CheckAll isCompleted) model@Model{..} =
  model { entries = newEntries }
    where
      newEntries = [ t { completed = isCompleted }
                   | t <- entries
                   ]
update (ChangeVisibility visibility) model =
  model { visibility = visibility }

view :: Address -> Model -> VTree
view send Model{..} = 
 div_
    [ class_ "todomvc-wrapper"
    , style_ "visibility:hidden;"
    ]
    [ section_
        [ class_ "todoapp" ]
        [ viewInput send field
        , viewEntries send visibility entries
        , viewControls send visibility entries
        ]
    , infoFooter
    ]

onClick :: IO () -> Attribute
onClick = on "click" . const

viewEntries :: Address -> String -> [ Entry ] -> VTree 
viewEntries send visibility entries =
  section_
    [ class_ "main"
    , style_ $ T.pack $ "visibility:" <> cssVisibility <> ";" 
    ]
    [ input_
        [ class_ "toggle-all"
        , type_ "checkbox"
        , attr "name" "toggle"
        , checked_ allCompleted
        , onClick $ send $ CheckAll (not allCompleted)
        ] []
      , label_
          [ attr "for" "toggle-all" ]
          [ text_ "Mark all as complete" ]
      , ul_ [ class_ "todo-list" ] $
         flip map (filter isVisible entries) $ \t ->
           viewKeyedEntry send t
      ]
  where
    cssVisibility = bool "visible" "hidden" (null entries)
    allCompleted = all (==True) $ completed <$> entries
    isVisible Entry {..} =
      case visibility of
        "Completed" -> completed
        "Active" -> not completed
        _ -> True

viewKeyedEntry :: Address -> Entry -> VTree
viewKeyedEntry = viewEntry

viewEntry :: (Msg -> IO ()) -> Entry -> VTree
viewEntry send Entry {..} = 
  li_
    [ class_ $ T.intercalate " " $ [ "completed" | completed ] ++ [ "editing" | editing ] ]
    [ div_
        [ class_ "view" ]
        [ input_
            [ class_ "toggle"
            , type_ "checkbox"
            , checked_ completed
            , onClick $ send (Check eid (not completed))
            ] []
        , label_
            [ on "dblclick" $ \_ -> send (EditingEntry eid True) ]
            [ text_ description ]
        , btn_
            [ class_ "destroy"
            , onClick $ send (Delete eid)
            ]
           []
        ]
    , input_
        [ class_ "edit"
        , prop "value" description
        , name_ "title"
        , id_ $ T.pack $ "todo-" ++ show eid
        , on "input" $ \(e :: Event) -> do
            Just ele <- fmap castToHTMLInputElement <$> getTarget e
            Just value <- getValue ele
            send (UpdateEntry eid value)
        , on "blur" $ \_ -> send (EditingEntry eid False)
        , onEnter $ send (EditingEntry eid False )
        ]
        []
    ]

viewControls :: Address -> String -> [ Entry ] -> VTree
viewControls send visibility entries =
  footer_  [ class_ "footer"
           , prop "hidden" (null entries)
           ]
      [ viewControlsCount entriesLeft
      , viewControlsFilters send visibility
      , viewControlsClear send entriesCompleted
      ]
  where
    entriesCompleted = length . filter completed $ entries
    entriesLeft = length entries - entriesCompleted

viewControlsCount :: Int -> VTree
viewControlsCount entriesLeft =
  span_ [ class_ "todo-count" ]
     [ strong_ [] [ text_ (show entriesLeft) ]
     , text_ (item_ ++ " left")
     ]
  where
    item_ = bool " items" " item" (entriesLeft == 1)


viewControlsFilters :: Address -> String -> VTree
viewControlsFilters send visibility =
  ul_
    [ class_ "filters" ]
    [ visibilitySwap send "#/" "All" visibility
    , text_ " "
    , visibilitySwap send "#/active" "Active" visibility
    , text_ " "
    , visibilitySwap send "#/completed" "Completed" visibility
    ]

visibilitySwap :: Address -> String -> String -> String -> VTree
visibilitySwap send uri visibility actualVisibility =
  li_ [ onClick $ send (ChangeVisibility visibility) ]
      [ a_ [ href_ $ T.pack uri
           , class_ $ T.concat [ "selected" | visibility == actualVisibility ]
           ] [ text_ visibility ]
      ]

viewControlsClear :: Address -> Int -> VTree
viewControlsClear send entriesCompleted =
  btn_
    [ class_ "clear-completed"
    , prop "hidden" (entriesCompleted == 0)
    , onClick $ send DeleteComplete
    ]
    [ text_ $ "Clear completed (" ++ show entriesCompleted ++ ")" ]

type Address = Msg -> IO ()

viewInput :: Address -> String -> VTree
viewInput send task =
  header_ [ class_ "header" ]
    [ h1_ [] [ text_ "todos" ]
    , input_
        [ class_ "new-todo"
        , placeholder "What needs to be done?"
        , autofocus True
        , prop "value" task
        , attr "name" "newTodo"
        , onInput $ \(x ::Event) -> do
            Just target <- fmap castToHTMLInputElement <$> getTarget x
            Just val <- getValue target
            send $ UpdateField val
        , onEnter $ send Add
        ] []
    ]

onEnter :: IO () -> Attribute
onEnter action = 
  on "keydown" $ \(e :: Event) -> do
    key <- getKeyCode (castToUIEvent e)
    when (key == 13) action

onInput :: (Event -> IO ()) -> Miso.Attribute
onInput = on "input"

onBlur :: (Event -> IO ()) -> Attribute
onBlur = on "blur" 

infoFooter :: VTree
infoFooter =
    footer_ [ class_ "info" ]
    [ p_ [] [ text_ "Double-click to edit a todo" ]
    , p_ []
        [ text_ "Written by "
        , a_ [ href_ "https://github.com/dmjio" ] [ text_ "David Johnson" ]
        ]
    , p_ []
        [ text_ "Part of "
        , a_ [ href_ "http://todomvc.com" ] [ text_ "TodoMVC" ]
        ]
    ]
