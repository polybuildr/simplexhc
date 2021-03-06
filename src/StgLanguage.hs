{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE InstanceSigs #-}

module StgLanguage where

import Control.Monad.Trans.Class
import Control.Lens
import Text.PrettyPrint as PP
import ColorUtils
import qualified Data.List.NonEmpty as NE
import qualified Text.Megaparsec as P
import qualified Text.Megaparsec.Pos as P.Pos

showStyle :: PP.Style
showStyle = PP.Style {
    mode = PP.PageMode,
    lineLength = 30,
    ribbonsPerLine = 1.5
}

mkNest :: Doc -> Doc
mkNest = nest 4

class Prettyable a where
    mkDoc :: a -> Doc

instance Prettyable Int where
  mkDoc = int

instance Prettyable a => Prettyable [a] where
  mkDoc xs = xs & fmap mkDoc & punctuate comma & hsep & parens

instance (Prettyable a, Prettyable b) => Prettyable (a, b) where
  mkDoc (a, b) = braces (mkDoc a PP.<> comma PP.<> mkDoc b)

newtype ConstructorName = ConstructorName { _getConstructorName :: String } deriving (Eq, Ord)
makeLenses ''ConstructorName

instance Show ConstructorName where
  show cons = _getConstructorName cons

instance Prettyable ConstructorName where
    mkDoc = text . show

newtype VarName = VarName { _getVariable :: String } deriving(Ord, Eq)

instance Prettyable VarName where
    mkDoc var = mkStyleTag (text "var:") <> (text (_getVariable var))

instance Show VarName where
    show = renderStyle showStyle . mkDoc

newtype RawNumber = RawNumber { _getRawNumber :: String }  deriving(Eq, Ord)
makeLenses ''RawNumber


instance Prettyable RawNumber where
  mkDoc (RawNumber num) = mkStyleTag (text "rawnum:") PP.<> text num PP.<> text "#"

instance Show RawNumber where
    show = renderStyle showStyle . mkDoc

data TokenType = TokenTypePlus | 
                 TokenTypeMinus | 
                 TokenTypeDiv | 
                 TokenTypeMultiply | 
                 TokenTypeVarName !VarName | 
                 TokenTypeConstructorName !ConstructorName | 
                 TokenTypeLet |
                 TokenTypeLetrec |
                 TokenTypeIn |
                 TokenTypeCase |
                 TokenTypeOf |
                 TokenTypeDefine |
                 TokenTypeUpdate !Bool | -- true: should update, false: no update
                 TokenTypeThinArrow |
                 TokenTypeFatArrow |
                 TokenTypeSemicolon |
                 TokenTypeOpenBrace |
                 TokenTypeCloseBrace |
                 -- | '('
                 TokenTypeOpenParen |
                 -- | ')'
                 TokenTypeCloseParen |
                 TokenTypeComma |
                 TokenTypeEquals | 
                 TokenTypeRawNumber !RawNumber deriving(Eq, Ord)


instance Show TokenType where
  show TokenTypePlus = "+"
  show TokenTypeMinus = "-"
  show TokenTypeDiv = "/"
  show TokenTypeMultiply = "*"
  show (TokenTypeVarName var) = show var
  show (TokenTypeConstructorName name) = show name
  show (TokenTypeRawNumber num) = show num
  show TokenTypeLet = "let"
  show TokenTypeLetrec = "letrec"
  show TokenTypeIn = "in"
  show TokenTypeCase = "case"
  show TokenTypeOf = "of"
  show TokenTypeDefine = "define"
  show (TokenTypeUpdate b) = "\\" ++ (if b then "u" else "n")
  show TokenTypeThinArrow = "->"
  show TokenTypeFatArrow = "=>"
  show TokenTypeEquals = "="
  show TokenTypeSemicolon = ";"
  show TokenTypeOpenBrace = "{"
  show TokenTypeCloseBrace = "}"
  show TokenTypeOpenParen = "("
  show TokenTypeCloseParen = ")"
  show TokenTypeComma = "}"


instance Prettyable TokenType where
    mkDoc = text . show
  
data Token = Token {
  _tokenType :: !TokenType
  -- HACK: for now, remove this and just use semi valid position given by the function
  -- in updatePos.
  -- , _tokenPos :: (P.Pos.SourcePos, P.Pos.SourcePos)
} deriving(Eq, Ord)


instance Prettyable Token where
    mkDoc (Token{..}) = (mkDoc _tokenType) 

instance (Show Token) where
    show = renderStyle showStyle . mkDoc

instance P.ShowToken Token where
    showTokens :: NE.NonEmpty Token -> String
    showTokens xs = renderStyle showStyle (hcat (fmap mkDoc (NE.toList xs)))

newtype StgInt = StgInt { unStgInt :: Int } deriving(Show, Eq)

instance Prettyable StgInt where
  mkDoc (StgInt i) = text . show $ i

data Atom = AtomInt !StgInt | AtomVarName !VarName deriving(Show)

instance Prettyable Atom where
    mkDoc (AtomInt n) = mkDoc n
    mkDoc (AtomVarName var) = mkDoc var

data Binding = Binding {
  _bindingName :: !VarName,
  _bindingLambda :: !Lambda
}
type Program = [Binding]


data Constructor = Constructor { _constructorName :: !ConstructorName,
                                 _constructorAtoms :: ![Atom]
                               }

instance Prettyable Constructor where
  mkDoc (Constructor name idents) = mkDoc name <+> (idents & map mkDoc & hsep)

instance Show Constructor where
  show = renderStyle showStyle . mkDoc

data IsLetRecursive = LetRecursive | LetNonRecursive deriving(Show, Eq)

data ExprNode = ExprNodeBinop !ExprNode !Token !ExprNode |
               ExprNodeFnApplication !VarName ![Atom] |
               ExprNodeConstructor !Constructor |
               ExprNodeLet !IsLetRecursive ![Binding] !ExprNode |
               ExprNodeCase !ExprNode ![CaseAltType] |
               ExprNodeInt !StgInt
      


data CaseAlt lhs = CaseAlt {
  _caseAltLHS :: !lhs,
  _caseAltRHS :: !ExprNode
}


instance Prettyable lhs => Prettyable (CaseAlt lhs) where
  mkDoc CaseAlt{..} = mkDoc _caseAltLHS <+>
                      text "->" <+>
                      mkDoc _caseAltRHS

instance Prettyable lhs => Show (CaseAlt lhs) where
    show = renderStyle showStyle . mkDoc

data ConstructorPatternMatch = ConstructorPatternMatch ConstructorName [VarName] deriving(Eq)

instance Prettyable ConstructorPatternMatch where
  mkDoc (ConstructorPatternMatch consName vars) = 
      mkDoc consName <+> (fmap mkDoc vars & punctuate comma & hsep & braces)

data CaseAltType = -- | match with a constructor: ConstructorName bindNames*
                      CaseAltConstructor !(CaseAlt ConstructorPatternMatch) |
                      -- | match with a number: 10 -> e
                      CaseAltInt !(CaseAlt StgInt) |
                      -- | match with a variable: x -> e
                      CaseAltVariable !(CaseAlt VarName) 



instance Prettyable CaseAltType where
  mkDoc (CaseAltConstructor a) = 
    mkDoc (_caseAltLHS a) <+>
    text "->"  <+>
    mkDoc (_caseAltRHS a) 

  mkDoc (CaseAltInt a) = mkDoc a
  mkDoc (CaseAltVariable a) = mkDoc a

instance Show CaseAltType where
  show = renderStyle showStyle . mkDoc

data Lambda = Lambda {
    _lambdaShouldUpdate :: !Bool,
    _lambdaFreeVarIdentifiers :: ![VarName],
    _lambdaBoundVarIdentifiers :: ![VarName],
    _lambdaExprNode :: !ExprNode
} 



instance Prettyable Lambda where
    mkDoc (Lambda{..}) = 
        freedoc <+> updatedoc <+>
        bounddoc <+> text "->" <+>
        (mkDoc _lambdaExprNode) where
            freedoc = (map mkDoc _lambdaFreeVarIdentifiers) & punctuate comma & hsep & braces
            bounddoc = (map mkDoc _lambdaBoundVarIdentifiers) & punctuate comma & hsep & braces
            updatedoc = PP.char '\\' <> (if _lambdaShouldUpdate then PP.char 'u' else PP.char 'n')

instance Show Lambda where
    show = renderStyle showStyle . mkDoc


makeLenses ''Token
makeLenses ''Binding
makeLenses ''Lambda
makeLenses ''CaseAlt
makeLenses ''Atom
makePrisms ''ExprNode
makePrisms ''TokenType
makePrisms ''CaseAltType
makeLenses ''VarName
makeLenses ''Constructor


instance Prettyable ExprNode where
    mkDoc  (ExprNodeFnApplication fnName atoms) =
        (mkDoc fnName) <+>
        (map mkDoc atoms & punctuate comma & hsep & braces)

    mkDoc (ExprNodeBinop eleft tok eright) = (tok ^. tokenType ^. to mkDoc)  <+>
                                             (mkDoc eleft) <+>
                                             (mkDoc eright)
    mkDoc (ExprNodeLet isrecursive bindings expr) = 
          letname <+>
          bindingsstr $$ 
          (text "in")  $$
          (expr & mkDoc) where
                        letname = PP.text (if isrecursive == LetNonRecursive then "let" else "letrec")
                        bindingsstr = map mkDoc bindings & vcat


    mkDoc (ExprNodeConstructor constructor) = mkDoc constructor

    mkDoc (ExprNodeInt n) = mkDoc n
    mkDoc (ExprNodeCase e alts) = text "case" <+> mkDoc e <+> text "of" <+> text "{" <+> (mkNest altsDoc)  <+> text "}" where
                                              altsDoc = fmap mkDoc alts & vcat

instance Show ExprNode where
    show = renderStyle showStyle . mkDoc


instance Prettyable Binding where
    mkDoc (Binding{..}) = 
                         (mkDoc _bindingName) <+> equals <+>
                         (_bindingLambda & mkDoc)


instance Show Binding where
    show = renderStyle showStyle . mkDoc
