module Pages.Recipe exposing (..)

import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as JP
import Parser exposing (..)
import Ui as Ui
import Update exposing (Msg(..), Timer)
import Util



-- TYPES --


type MealType
    = Vegetarian
    | Vegan


type alias Flags =
    { recipes : Decode.Value
    }


type alias Ingredient =
    { ingredient : String
    , quantity : String
    , unit : String
    , id : String
    }


type alias Instruction =
    { original : String
    }


type alias Recipe =
    { belongs_to : String -- "main" | "salad" etc
    , date_made : String
    , ease_of_making : String
    , imgs : List String
    , meal_type : MealType
    , name : String
    , rating : String
    , original_recipe : String
    , serves : String
    , slug : String
    , time : String
    , ingredients : List Ingredient
    , instructions : List Instruction
    }



-- Getters


nameFromSlug recipes slug =
    case recipes of
        Just recipesUnwrapped ->
            case Dict.get slug recipesUnwrapped of
                Just recipe ->
                    recipe.name

                Nothing ->
                    ""

        Nothing ->
            ""



-- PARSER --


type alias InstructionParsed =
    { timer : Timer
    , chunks : List InstructionChunk
    }


type alias InstructionChunk =
    { id : String
    , val : String
    }


{-| Parses the timer that MAY exist at the beginning of an instruction string
There are some hacks here because I still don't entirely understand parsing. (see timerType)

[&: 00:05:00] Cook the onions for 5 minutes.
^-----------^-------------------------------

-}
parseTimer =
    oneOf
        [ succeed Timer
            |. spaces
            |. symbol "[&:"
            |. spaces
            |= (getChompedString <| chompUntil "|")
            |. symbol "|"
            |. spaces
            |= (getChompedString <| chompUntil "]")
            |. symbol "]"
            |= succeed 0
            |> andThen
                (\res ->
                    succeed <|
                        { res
                            | step = String.trim res.step
                            , time = Util.strToSec res.timeString
                        }
                )
        , succeed Timer
            |= succeed ""
            |= succeed ""
            |= succeed 0
        ]


parseChunk =
    Parser.loop [] parseChunkHelp


parseChunkHelp revStmts =
    oneOf
        [ succeed (\stmt -> Loop (stmt :: revStmts))
            |= parseIngredientChunk
        , succeed (\stmt -> Loop (stmt :: revStmts))
            |= parseUntilIngredient
        , succeed (\stmt -> Loop (stmt :: revStmts))
            |= parseUntilPeriod
        , succeed ()
            |> Parser.map (\_ -> Done (List.reverse revStmts))
        ]


{-| Parses an instruction string until it reaches an ingredient:
Get a bowl and chop [#: c | celery ] into ....
--------------------^-------------------------
-}
parseUntilIngredient =
    succeed InstructionChunk
        |= succeed ""
        |= (getChompedString <| chompUntil "[")
        |. chompIf (\c -> c == '[')


{-| Parses an instruction string until it reaches an ingredient:
Mix the soup until it warms evenly through.
------------------------------------------^-----

This is necessary for parsing normal strings after all ingreidents
have been parsed by `parseIngredientChunk` or for steps that
don't have any ingredients that need to be parsed in the first place.

-}
parseUntilPeriod =
    succeed InstructionChunk
        |= succeed ""
        |= (getChompedString <| chompUntil ".")
        |. chompIf (\c -> c == '.')
        |> andThen (\res -> succeed <| { res | val = String.append res.val "." })


{-| Parses an ingredient from the instruction string
Get a bowl and chop [#: c | celery ] into ....
------------------- ^==============^ ------

creates an InstructionChunk of {id: "c", val: "celery"}

andThen, in the case that the original string has excess space in the markup:

...and chop [#:...c |... celery ] ...)
...------------^^^---^^^-------------

trim any excess whitespace around the id and the val
{id: " c ", val: " celery "} -> {id: "c", val: "celery"}

-}
parseIngredientChunk =
    succeed InstructionChunk
        |. symbol "#:"
        |. spaces
        |= (getChompedString <| chompUntil " ")
        |. spaces
        |. symbol "|"
        |. spaces
        |= (getChompedString <| chompUntil "]")
        |. symbol "]"
        |> andThen
            (\res -> succeed <| { res | val = String.trim res.val, id = String.trim res.id })


{-| Groups parsers together to result in creating an InstructionParsed type.
-}
parseEverything =
    succeed InstructionParsed
        |= parseTimer
        |= parseChunk


runParser str =
    Parser.run parseEverything str



-- DECODERS --


decodeInstruction : Decoder Instruction
decodeInstruction =
    Decode.succeed Instruction
        |> JP.required "original" Decode.string


decoderIngredient : Decoder Ingredient
decoderIngredient =
    Decode.succeed Ingredient
        |> JP.required "ingredient" Decode.string
        |> JP.required "quantity" Decode.string
        |> JP.required "unit" Decode.string
        |> JP.required "id" Decode.string


recipesDecoder : Decoder (Dict.Dict String Recipe)
recipesDecoder =
    Decode.dict decodeRecipe


decodeMealType : Decoder MealType
decodeMealType =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "vegetarian" ->
                        Decode.succeed Vegetarian

                    "vegan" ->
                        Decode.succeed Vegan

                    _ ->
                        Decode.fail ("Unrecognized mealtype " ++ s)
            )


decodeRecipe : Decoder Recipe
decodeRecipe =
    Decode.succeed Recipe
        |> JP.required "belongs_to" Decode.string
        |> JP.required "date_made" Decode.string
        |> JP.required "ease_of_making" Decode.string
        |> JP.required "imgs" (Decode.list Decode.string)
        |> JP.required "meal_type" decodeMealType
        |> JP.required "name" Decode.string
        |> JP.required "rating" Decode.string
        |> JP.required "original_recipe" Decode.string
        |> JP.required "serves" Decode.string
        |> JP.required "slug" Decode.string
        |> JP.required "time" Decode.string
        |> JP.required "ingredients" (Decode.list decoderIngredient)
        |> JP.required "instructions" (Decode.list decodeInstruction)



-- VIEWS --


unwrapRecipes model fn =
    case model.recipes of
        Nothing ->
            div [] [ text "The recipes did not load. Go print a Debug.log in `init`" ]

        Just recipes ->
            fn recipes


viewHero recipe =
    let
        url =
            "url(/imgs/" ++ recipe.slug ++ "-hero.JPG)"
    in
    section
        [ class "viewHero"
        , style "background-image" url
        ]
        []


viewTimers model =
    let
        filteredTimers =
            List.filter (\t -> t.time > 0) model.timers

        timerText t =
            t.step ++ " " ++ Util.intToSec t.time

        mappedTimers =
            List.map
                (\t -> div [ class "timer" ] [ text <| timerText t ])
                filteredTimers
    in
    div [ class "timers" ] mappedTimers



-- Page: RecipeList ------------------------------------------------------------


viewList model =
    unwrapRecipes model
        (\recipes ->
            let
                rList recipe =
                    li [] [ a [ href ("recipe/" ++ recipe.slug) ] [ text recipe.name ] ]
            in
            section [ class "RecipeList" ]
                [ ul [ class "columns" ] (List.map rList (Dict.values recipes))
                ]
        )



-- Page: RecipeSingle -----------------------------------------------------------


viewImages : Recipe -> Html msg
viewImages recipe =
    let
        mapImgs i =
            div
                [ class "photo"
                , style "background-image" ("url(/imgs/" ++ recipe.slug ++ "-" ++ i)
                ]
                []
    in
    section [ class "photos" ] (List.map mapImgs recipe.imgs)



-- FIXME: remove inline styles


{-| viewInstructions does a few things:

  - Parse and display a recipe's instructions.
  - Handle rendering the timer and active step.
  - Handle creation of timers.
    |

-}
viewInstructions : Recipe -> List Timer -> Int -> Html Msg
viewInstructions recipe timers activeStep =
    let
        -- FIXME: abstract buildClass functionality into a single function.
        buildClass idx =
            if activeStep == idx then
                "instruction active"

            else
                "instruction"

        buildInstructions parsedInstructions =
            let
                -- only show timer if it's not in use
                -- loop through timers and check if current chunk is in there.
                -- FIXME rename :"chunk"
                makeTimer chunk =
                    if not (List.member chunk.timer timers) then
                        div
                            [ class "timer-icon"
                            , onClick (AddTimer chunk.timer)
                            ]
                            [ text "T: " ]

                    else
                        div [ class "timer-null" ] []

                makeInstruction i =
                    if String.isEmpty i.id then
                        span [] [ text i.val ]

                    else
                        span [ style "font-weight" "bold" ] [ text i.val ]
            in
            case parsedInstructions of
                Ok c ->
                    div [ class "instruction-and-timer" ]
                        [ div [ class "instruction-compiled" ] (List.map makeInstruction c.chunks)
                        , makeTimer c
                        ]

                Err _ ->
                    div [] [ text <| Debug.toString parsedInstructions ]

        mapInstructions index el =
            let
                stepNum =
                    (String.fromInt <| (1 + index)) ++ ". "

                stepText =
                    div []
                        [ div [ style "display" "flex" ]
                            [ span
                                [ class "instruction-num" ]
                                [ text stepNum ]
                            , buildInstructions <| runParser el.original
                            ]
                        ]
            in
            div [ class (buildClass index), onClick (SetCurrentStep index) ] [ stepText ]
    in
    section [ class "instr-ingr-section", style "flex" "1.5" ]
        [ Ui.sectionHeading "Instructions"
        , div [ class "instructions-group" ]
            [ div [] (List.indexedMap mapInstructions recipe.instructions)
            ]
        ]


viewIngredients : Recipe -> Html msg
viewIngredients recipe =
    let
        mapIngr i =
            div [ class "ingredient" ]
                [ div [ class "name" ] [ text i.ingredient ]
                , div [ class "quant-unit" ]
                    [ div [ class "quant" ] [ text i.quantity ]
                    , div [ class "unit" ] [ text i.unit ]
                    ]
                ]
    in
    section [ class "instr-ingr-section" ]
        [ Ui.sectionHeading "Ingredients"
        , div [ class "ingredients" ]
            [ div [ class "instructions-list" ] (List.map mapIngr recipe.ingredients)
            ]
        ]


viewSingle model recipeName =
    let
        viewIngrAndInstr recipe =
            div [ class "instruction-ingredients" ]
                [ viewInstructions recipe model.timers model.currentStep
                , div [ class "separator" ] []
                , viewIngredients recipe
                , viewTimers model
                ]
    in
    unwrapRecipes
        model
        (\recipes ->
            case Dict.get recipeName recipes of
                Just recipe ->
                    section [ class "RecipeSingle" ]
                        [ viewHero recipe
                        , section [ class "container" ]
                            [ viewIngrAndInstr recipe
                            , viewImages recipe
                            ]
                        ]

                Nothing ->
                    -- FIXME: Add a 404 redirect.
                    div [] [ text "RECIPE NOT FOUND! 404." ]
        )
