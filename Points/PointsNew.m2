-- -*- coding: utf-8 -*-
newPackage(
	"PointsNew",
    	Version => "1.9", 
    	Date => "9 January 2014",
    	Authors => {
	     {Name => "Samuel Lundqvist", Email => "samuel@math.su.se", HomePage => "http://www.math.su.se/~samuel"}
	     },
    	Headline => "Computing with sets of affine points and functionals (i.e. FGLM conversion)",
    	DebuggingMode => true
    	)
-- Current developers Samuel Lundqvist
-- Past developers Gregory G. Smith, Mike Stillman, Stein A. Strømme
-- Contributors 
-- Acknowledgements Based upon the old Points package by the three past developers above.
-- Especially, the code for reduceColumn and part of "Points" is taken from there. 
export {
     pointsMat,
     points,
     pointsByIntersection,
     makeRingMaps,
     nfPoints,
     separators,
     FGLM,
     stdmons,
     multmatrices,
     multmatricesGB,
     pointsNew,
     getEssGens
     }


debug Core

makeRingMaps = method (TypicalValue => List)
makeRingMaps (Matrix, Ring) := List => (M,R) -> (
     K := coefficientRing R;
     pts := entries transpose M;
     apply(pts, p -> map(K, R, p))
     )

reduceColumn := (M,Mchange,H,c) -> (
     -- M is a mutable matrix
     -- Mchange is either null, or a matrix with same number of columns as M
     -- H is a hash table: H#r == c if column c has pivot for row r 
     -- returns true if the element reduces to 0
     M = raw M;
     if Mchange =!= null then Mchange = raw Mchange;
     r := rawNumberOfRows M - 1;
     while r >= 0 do (
	  a := M_(r,c);
	  if a != 0 then (
	       -- is there a pivot?
	       if not H#?r then (
		    b := 1//a;
		    rawMatrixColumnScale(M, b, c, false);
		    if Mchange =!= null then rawMatrixColumnScale(Mchange, b, c, false);		    
		    H#r = c;
		    return false;
		    )
	       else (
	       	    pivotc := H#r;
	       	    rawMatrixColumnChange(M, c, -a, pivotc, false);
		    if Mchange =!= null then rawMatrixColumnChange(Mchange, c, -a, pivotc, false);
	       ));
     	  r = r-1;
	  );
     true
     )



multmatrices = method (TypicalValue => List)
multmatrices (List, GroebnerBasis, Ring) := (std, Gb, R) -> (
     --Gb := forceGB matrix {gblist};
     K := coefficientRing R;
     s := #std;
     --print s;
     --m := 0;
     l := 0;
     RtoK := map(K,R);
     bb := {}; --The list of matrices to return 
     for i from 0 to #(gens R)-1 do (
	  m :=  mutableMatrix map(K^s, K^s, 0);
	  for j from 0 to s-1 do (
	       l = flatten entries (coefficients ((R_i * std#j) % Gb, Monomials => std))_1;
	       scan(#l, k -> m_(j,k) = RtoK(l#k));
	  );	
     	  bb = append (bb, matrix m); --We don't want it to be mutable anymore.
     );	   
     return bb;
)
	       

getCoefficientVector := (varIndex, cv, K, multMatrix, s, connectionvector) -> (
     -- varIndex is the index of the variable we are multiplying with monomial with.
     -- cv is coefficient vector of the monomial.
     -- K is the field that we are performing computations over. 
     -- multMatrix is the multiplication matrix with respect to the variable.
     -- s is the k-dimension of the ring.
     -- returns the coefficientvector of variable*monomial from multMatrix.
     -- varIndex = - 1 represents the unit
     if (varIndex == -1) then (
	 --l := matrix {flatten ({1_K,toList((s-1):0_K)})};
	 -- return l	
	  return matrix {connectionvector};
	  );
       return cv * multMatrix;
     )
	       
	       
addNewMonomial := (M,col,monom,maps) -> (
     -- M is an s by s+1 matrix, s=#points
     -- monom is a monomial
     -- maps is a list of s ring maps, which will give the values
     --  of the monom at the points
     -- replaces the 'col' column of M with the values of monom
     --    at the s points.
     scan(#maps, i -> M_(i,col) = maps#i monom)
     )

pointsByIntersection = method(TypicalValue => List)
pointsByIntersection (Matrix,Ring) := (M,R) -> (
     flatten entries gens gb intersect apply (
       entries transpose M, p -> ideal apply(#p, i -> R_i - p#i)))

-- Changes from the old code (2008): 
-- Bugfix: All variables are now local.
-- Returns the *inverse* of the stds evaluated at points.
-- Returns the stds as a list instead of as matrix.
pointsMat = method()
pointsMat(Matrix,Ring) := (M,R) -> (
     -- The columns of M form the points.  M should be a matrix of size
     -- n by s, where n is the number of variables of R
     K := coefficientRing R;
     s := numgens source M;
     -- The local data structures:
     -- (P,PC) is the matrix which contains the elements to be reduced
     -- Fs is used to evaluate monomials at the points
     -- H is a hash table used in Gaussian elimination: it contains the
     --    pivot columns for each row
     -- L is the sum of monomials which is still to be done
     -- Lhash is a hashtable: LhashK := coefficientRing R;#monom = i means that only 
     --    R_i*monom, ..., R_n*monom should be considered
     -- G is a list of GB elements
     -- inG is the ideal of initial monomials for the GB
     Fs := makeRingMaps(M,R);
     P := mutableMatrix map(K^s, K^(s+1), 0);
     H := new MutableHashTable; -- used in the column reduction step
     Lhash := new MutableHashTable; -- used to determine which monomials come next
     L := 1_R;
     Lhash#L = 0; -- start with multiplication by R_0
     thiscol := 0;
     inG := trim ideal(0_R);
     inGB := forceGB gens inG;
     Q := {}; -- the list of standard monomials
     --ntimes := 0;
     while (L = L % inGB) != 0 do (
	  --ntimes = ntimes + 1;
	  --if #Q === s then print "got a basis";
	  --print("size of L = "| size(L));
	  -- First step: get the monomial to consider
	  monom := someTerms(L,-1,1);
	  L = L - monom;
	  -- Now fix up the matrix P
          addNewMonomial(P,thiscol,monom,Fs);
          isLT := reduceColumn(P,null,H,thiscol);
	  if isLT then (
	       -- we add to G, inG
	       inG = inG + ideal(monom);
	       inGB = forceGB gens inG;
	       )
	  else (
	       -- we modify L, Lhash, thiscol, and also PC
	       Q = append(Q, monom);
	       f := sum apply(toList(Lhash#monom .. numgens R - 1), i -> (
			 newmon := monom * R_i;
			 Lhash#newmon = i;
			 newmon));
	       L = L + f;
	       thiscol = thiscol + 1;
	       )
	  );
     --print("ntimes "|ntimes|" std+inG "|#Q + numgens inG);
     stds := transpose matrix{Q};
     A := inverse transpose matrix{apply(Fs, f -> f stds)};
     (A, Q)
     )
 
-- Changes from the old code (2008): 
-- Bugfix: All variables are now local.
-- Existing bug: Assuming R_0<R_1<..., which does not need to be true.
points = method()
points (Matrix,Ring) := (M,R) -> (
     -- The columns of M form the points.  M should be a matrix of size
     -- n by s, where n is the number of variables of R
     K := coefficientRing R;
     s := numgens source M;
     -- The local data structures:
     -- (P,PC) is the matrix which contains the elements to be reduced
     -- Fs is used to evaluate monomials at the points
     -- H is a hash table used in Gaussian elimination: it contains the
     --    pivot columns for each row
     -- L is the sum of monomials which is still to be done
     -- Lhash is a hashtable: Lhash#monom = i means that only 
     --    R_i*monom, ..., R_n*monom should be considered
     -- G is a list of GB elements
     -- inG is the ideal of initial monomials for the GB
     Fs := makeRingMaps(M,R);
     P := mutableMatrix map(K^s, K^(s+1), 0);
     PC := mutableMatrix map(K^(s+1), K^(s+1), 0);
     for i from 0 to s-1 do PC_(i,i) = 1_K;
     H := new MutableHashTable; -- used in the column reduction step
     Lhash := new MutableHashTable; -- used to determine which monomials come next
     L := 1_R;
     Lhash#L = 0; -- start with multiplication by 1_R
     thiscol := 0;
     G := {};
     inG := trim ideal(0_R);
     inGB := forceGB gens inG;
     Q := {}; -- the list of standard monomials
     nL := 1;
     while L != 0 do (
	  -- First step: get the monomial to consider
	  L = L % inGB;
	  monom := someTerms(L,-1,1);
	  L = L - monom;
	  -- Now fix up the matrices P, PC
          addNewMonomial(P,thiscol,monom,Fs);
	  rawMatrixColumnScale(raw PC, raw(0_K), thiscol, false);
	  PC_(thiscol,thiscol) = 1_K;
          isLT := reduceColumn(P,PC,H,thiscol);
	  if isLT then (
	       -- we add to G, inG
	       inG = inG + ideal(monom);
	       inGB = forceGB gens inG;
	       g := sum apply(toList(0..thiscol-1), i -> PC_(i,thiscol) * Q_i);
	       G = append(G, PC_(thiscol,thiscol) * monom + g);
	       )
	  else (
	       -- we modify L, Lhash, thiscol, and also PC
	       Q = append(Q, monom);
	       f := sum apply(toList(Lhash#monom .. numgens R - 1), i -> (
			 newmon := monom * R_i;
			 Lhash#newmon = i;
			 newmon));
	       nL = nL + size(f);
	       L = L + f;
	       thiscol = thiscol + 1;
	       )
	  );
--     print("number of monomials considered = "|nL);
     (Q,inG,G)
     )
 
getEssGens = method()
getEssGens (Matrix, Ring) := (M,R) -> (
       K := coefficientRing R;
     s := numgens source M;
     Fs := makeRingMaps(M,R);
     P := mutableMatrix map(K^s, K^(s+1), 0);
     PC := mutableMatrix map(K^(s+1), K^(s+1), 0);
     for i from 0 to s-1 do PC_(i,i) = 1_K;
     H := new MutableHashTable; -- used in the column reduction step
     thiscol := 0;
     esslist := {};   --The essential variables listed sorted ascending.
     nonesspoly := 0_K; -- The nonessential variables. Not necessarily sorted.
     l := sum(apply(toList(0 .. numgens R - 1),i-> R_i));
     m := 0;
	 while l != 0 do (
	     m = someTerms(l,-1,1);
    	     l = l - m;
             addNewMonomial(P,thiscol,m,Fs);
	     rawMatrixColumnScale(raw PC, raw(0_K), thiscol, false);
	     PC_(thiscol,thiscol) = 1_K;
	     isLT := reduceColumn(P,PC,H,thiscol);
	     if isLT then (
		 nonesspoly = nonesspoly + m;
	     --do nothing;
	     ) else (
	       -- we modify L, Lhash, thiscol, and also PC
	       esslist = append(esslist, m);
	      if (#esslist == s-1) then (
		  return (esslist, flatten entries (monomials (nonesspoly + l)));
		  );
	        thiscol = thiscol + 1;
	       );
	);
  if (nonesspoly == 0) then (
      return (esslist, {});
      );
  return (esslist, flatten entries (monomials (nonesspoly)));
  )
  


pointsNew = method()
pointsNew (Matrix,Ring) := (M,R) -> (
     -- The columns of M form the points.  M should be a matrix of size
     -- n by s, where n is the number of variables of R
     K := coefficientRing R;
     s := numgens source M;
     -- The local data structures:
     -- (P,PC) is the matrix which contains the elements to be reduced
     -- Fs is used to evaluate monomials at the points
     -- H is a hash table used in Gaussian elimination: it contains the
     --    pivot columns for each row
     -- L is the sum of monomials which is still to be done
     -- Lhash is a hashtable: Lhash#monom = i means that only 
     --    essgens_i*monom, ..., essgens_n*monom should be considered
     -- G is a list of GB elements
     -- inG is the ideal of initial monomials for the GB
     essgens := {};
     nonessgens := {};
     essGenCall := false;
     if (s < numgens R and numgens R > 50) then (
     	 (essgens,nonessgens) = getEssGens(M,R);
	 essGenCall = true;
	 ) else (
	 essgens = sort gens R; --sorts in ascending wrt the monomial order of R
	 essGenCall = false;
	 );
	 
     Fs := makeRingMaps(M,R);
     P := mutableMatrix map(K^s, K^(s+1), 0);
     PC := mutableMatrix map(K^(s+1), K^(s+1), 0);
     for i from 0 to s-1 do PC_(i,i) = 1_K;
     H := new MutableHashTable; -- used in the column reduction step
     Lhash := new MutableHashTable; -- used to determine which monomials come next
     L := 1_R;
     Lhash#L = 0; -- start with multiplication by essgen_0.
   
 
     thiscol := 0;
     G := {};
     inG := trim ideal(0_R);
     inGB := forceGB gens inG;
     Q := {}; -- the list of standard monomials
     nL := 1;
     monom :=0;
     g := 0;
     isLT := 0;
     f:=0;
     while L != 0 do (
	  -- First step: get the monomial to consider
	  L = L % inGB;
	  monom = someTerms(L,-1,1);
	  L = L - monom;
	  -- Now fix up the matrices P, PC
          addNewMonomial(P,thiscol,monom,Fs);
	  rawMatrixColumnScale(raw PC, raw(0_K), thiscol, false);
	  PC_(thiscol,thiscol) = 1_K;
          isLT = reduceColumn(P,PC,H,thiscol);
	  if isLT then (
	       -- we add to G, inG	  
	       inG = inG + ideal(monom);
	       inGB = forceGB gens inG;
	       g = sum apply(toList(0..thiscol-1), i -> PC_(i,thiscol) * Q_i);
	       G = append(G, PC_(thiscol,thiscol) * monom + g);
	       )
	  else (
	       -- we modify L, Lhash, thiscol, and also PC
	       Q = append(Q, monom);
	       f = sum apply(toList(Lhash#monom .. #essgens - 1), i -> (
			 newmon := monom * essgens_i;
			 Lhash#newmon = i;
			 newmon));
	       nL = nL + size(f);
	       L = L + f;
	       thiscol = thiscol + 1;
	       )
	  );
      --We end up by computing the Groebner basis elements with leadterm
      --in nonessgen. For efficiency purposes, they were not added to L in the
      --first step. One could also use that we already have reduced them in
      --the getEssGen-procedure.
    if (essGenCall == true) then (
    L = sum apply(toList(0..#nonessgens -1), i-> (nonessgens_i));	      
         while (L != 0 ) do (
	     monom = someTerms(L,-1,1);
	     L = L - monom;
	     addNewMonomial(P,thiscol,monom,Fs);
	     rawMatrixColumnScale(raw PC, raw(0_K), thiscol, false);
	     PC_(thiscol,thiscol) = 1_K;
             reduceColumn(P,PC,H,thiscol);	  
	     inG = inG + ideal(monom);
	    -- inGB = forceGB gens inG;
	     g = sum apply(toList(0..thiscol-1), i -> PC_(i,thiscol) * Q_i);
	     G = append(G, PC_(thiscol,thiscol) * monom + g);
      );
    );  
--     print("number of monomials considered = "|nL);
     (Q,inG,G)
     )


-- The separators of the points as linear combinations of the standard monomials
-- stds are the standard monomials returned by pointsMat
-- Ainv is the inverse of the matrix returned by pointsMat
separators = method()
separators (Matrix, Matrix) := (stds, Ainv) -> (
     transpose (Ainv) * (matrix entries stds)
     )


-- The normal form of a polynomial using Ainv and linear algebra
-- p is the polynomial of which we want to compute nf
-- phi are the ring maps returned from makeRingMaps 
-- stds are the standard monomials returned by pointsMat
-- Ainv is the inverse of the matrix returned by pointsMat
nfPoints = method()
nfPoints (RingElement, List, List, Matrix) := (p, phi, stds, Ainv) -> (
     --Evaluate the vector on the points
     v := transpose matrix {apply (phi, r -> r p)};
     w := Ainv * v;
     --Fix the stds
     stdsniceform := matrix {stds};
     print(stdsniceform);
     w;
     print(w);
     --return the normal form
     first (first entries (stdsniceform*w))
     )


-- Return the stdmons as a list
stdmons = method()
stdmons(PolynomialRing, GroebnerBasis) := (S,Gb) -> (
     I := monomialIdeal(leadTerm (Gb));
     basisSmodI := flatten (entries (basis (S/I)));
     -- we want the monomials, not the residues, so we map from S/I to S. 
     SmodItoS := map(S,S/I);
     apply(basisSmodI, i -> SmodItoS(i))
     )

--getEssGens = method() ->

FGLM = method()
FGLM (GroebnerBasis, PolynomialRing, Option) := (GS,S,monOrd) -> (   
     basisS := stdmons (S,GS);
     s := length basisS;
      K := coefficientRing S;
      connectionvector := flatten toList (1_K,toList(s-1:0_K));
    return multmatricesGB(multmatrices(basisS, GS, S), 
	connectionvector, S, monOrd); --ok even if s-2<0
    )

--Removes elements at the end of the list for which supp(m) > #copies.
--These elements are multiplies of ini(I) and should not be considered, cf the
--trick in the FGLM-paper.
removeElements := (L) -> (
    Lleast := 0;
     while L != {} do (
	  Lleast = first(L);
       if (#support(Lleast#0) > (Lleast#1)#2) then (
       L = drop(L,1);
       ) else (
       return L;
       );
  );
  return L;   
)
--multmatricesGB = method()
--multmatricesGB (List,Number, PolynomialRing, Option) := (mm,s,S,monOrd) -> (
multmatricesGB = method()
multmatricesGB (List, List, PolynomialRing, Option) := 
(mm,connectionvector,S,monOrd) -> (
      --Determine the standard monomials.
     --GSl :=  flatten entries gens GS;
     --from now on, we will compute over the ring R;
     s := length connectionvector;
     R := newRing(S, monOrd);
     --RtoS := map(S,R);
     K := coefficientRing R;
     StoK := map(K,S);
     -- The local data structures:
     -- (P,PC) is the matrix which contains the elements to be reduced
     -- Fs is used to evaluate monomials at the points
     -- H is a hash table used in Gaussian elimination: it contains the
     --    pivot columns for each row
     -- L is the monomials to be done. An element in L is of the form
     -- (monom, (variable, coefflist, i)), where monom and variable is in R and
     -- the coefficientlist is the coefficient of (monom/variable) in basisS and
     -- i is the number of copies of the element in L.
     -- monom is only used for keeping L sorted and to be able to use MergePairs.
     
     -- G is a list of GB elements
     -- inG is the ideal of initial monomials for the GB
     --Fs := makeRingMaps(M,R);
     P := mutableMatrix map(K^s, K^(s+1), 0);
     PC := mutableMatrix map(K^(s+1), K^(s+1), 0);
     for i from 0 to s-1 do PC_(i,i) = 1_K;
     H := new MutableHashTable; -- used in the column reduction step     
     -- essgens := getEss(gens R);
     essgens := gens R; --When removing this, the list below must also be changed 
     -- i.e. All noness should be inserted into L.
     L := {(1_R, (-1, {1},1))}; -- the list of potential elements. The list {1} is dummy.  
     Q := {}; -- the list of standard monomials
     thiscol := 0;
     G := {}; -- the list of Groebner basis elements to return
     numList := 1;
    Lleast := 0;
    cv := 0;
    monom := 0;
    while L != {} do (
	  -- First step: get the monomial to consider
	  Lleast = L#0;
	  L = drop(L,1);
	   --Pick the minimal elementet in L.
	  -- Now fix up the matrices P, PC
	  -- We are multiplying with (Lleast#1)#0;
          cv = getCoefficientVector(
	       (Lleast#1)#0, (Lleast#1)#1, K, mm#((Lleast#1)#0),s,connectionvector);	  
	  scan(s, i -> P_(i,thiscol) = cv_(0,i)); --add the column to P
	  rawMatrixColumnScale(raw PC, raw(0_K), thiscol, false);
	  PC_(thiscol,thiscol) = 1_K;
          isLT := reduceColumn(P,PC,H,thiscol);
	  monom = (Lleast#0);
	  if isLT then (
	       -- we add to G
	       g := sum apply(toList(0..thiscol-1), i -> PC_(i,thiscol) * Q_i);
	       G = append(G, PC_(thiscol,thiscol) * monom + g);
	       )
	  else (
	       -- we modify L and thiscol
	       Q = append(Q, monom);	  
	       newList := {};
	       for i from 0 to #essgens - 1 do (
	       	  numList = numList + 1;
	       	  newList = prepend((monom * essgens_i, (i, cv,1)),newList);
		  );
	       L = mergePairs(L,newList, (v,w)->(v#0,v#1,v#2 + w#2));

	       thiscol = thiscol + 1;
	       );
	  L = removeElements(L);
	  );
     --print("number of monomials considered = " numList);
     (R,G,Q)
     )



     
     
beginDocumentation()

document {
     Key => PointsNew,
     "A package to compute with points in affine and projective spaces",
     {*
     Subnodes => {
	  -- Mike wanted this: TO (points,Matrix,Ring)
	  }
     *}
     }
document {
     Key => {nfPoints, (nfPoints,RingElement,List,List,Matrix)},
     Headline => "Normal form wrt standard monomials using linear algebra",
     Usage => "makeRingMaps(p,phi,std,Ainv)",
     Inputs => {
     	  "p" => RingElement => "The polynomial for which we want to compute the normal form",
	  "phi" => List => "The ring maps",
	  "std" => Matrix => "in which each column consists of the coordinates of a point",
	  "Ainv" => Matrix => "Inverse of the matrix achieved by evaluating the standard monomials on the input points",
	  },
     Outputs => {RingElement => "The normal form of f wrt the standard monomials"},
     "Computing normal forms with respect to a vanishing ideal of points should be done by linear algebra and not by means of a Gröbner basis. 
     The timing below indicates that the speedup is drastic, even for toy examples. ",
     EXAMPLE lines ///
     
     M = random(ZZ^10, ZZ^15);
     R = QQ[a..j];
     (A, std) = pointsMat(M, R);
     phi = makeRingMaps(M,R);
     Ainv = inverse A;
     f = b^3*c^10;
     timing f1 = nfPoints(f, phi, std, Ainv)
     --0.005261 seconds
     (Q,inG,G) = points(M,R)
     Gb = forceGB (matrix {G});
     timing f2= f % Gb
     --14.7422 seconds
     --The normal forms are the same
     f1 == f2
     --True
     ///
     }

document {
     Key => {makeRingMaps, (makeRingMaps,Matrix,Ring)},
     Headline => "evaluation on points",
     Usage => "makeRingMaps(M,R)",
     Inputs => {
     	  "M" => Matrix => "in which each column consists of the coordinates of a point",
	  "R" => PolynomialRing => "coordinate ring of the affine space containing the points",
	  },
     Outputs => {List => "of ring maps corresponding to evaluations at each point"},
     "Giving the coordinates of a point in affine space is equivalent to giving a
     ring map from the polynomial ring to the ground field: evaluation at the point.  Given a
     finite collection of points encoded as the columns of a matrix,
     this function returns a corresponding list of ring maps.",
     EXAMPLE lines ///
     M = random(ZZ^3, ZZ^5)
     R = QQ[x,y,z]
     phi = makeRingMaps(M,R)
     phi#2
     ///
     }



document {
     Key => {points, (points,Matrix,Ring)},
     Headline => "produces the ideal and initial ideal from the coordinates
     of a finite set of points",
     Usage => "(Q,inG,G) = points(M,R)",
     Inputs => {
     	  "M" => Matrix => "in which each column consists of the coordinates of a point",
	  "R" => PolynomialRing => "coordinate ring of the affine space containing the points",
	  },
     Outputs => {
          "Q" => List => "list of standard monomials",
 	  "inG" => Ideal => "initial ideal of the set of points",
 	  "G" => List => "list of generators for Grobner basis for ideal of points"
 	  },
     "This function uses the Buchberger-Moeller algorithm to compute a grobner basis
     for the ideal of a finite number of points in affine space.  Here is a simple
     example.",
     EXAMPLE lines ///
      M = random(ZZ^3, ZZ^5)
     R = QQ[x,y,z]
     (Q,inG,G) = points(M,R)
     monomialIdeal G == inG
     ///,
     PARA{},
     "Next a larger example that shows that the Buchberger-Moeller algorithm in ",
     TT "points", " may be faster than the alternative method using the intersection
     of the ideals for each point.",
     EXAMPLE lines ///
     R = ZZ/32003[vars(0..4), MonomialOrder=>Lex]
     M = random(ZZ^5, ZZ^150)
     time J = pointsByIntersection(M,R);
     time C = points(M,R);
     J == C_2  
     ///,
     SeeAlso => {pointsByIntersection}
     }



document {
     Key => {pointsMat, (pointsMat,Matrix,Ring)},
     Headline => "produces the matrix of values of the standard monomials
     on a set of points",
     Usage => "(A,stds) = pointsMat(M,R)",
     Inputs => {
     	  "M" => Matrix => "in which each column consists of the coordinates of a point",
	  "R" => PolynomialRing => "coordinate ring of the affine space containing the points",
	  },
     Outputs => {
          "A" => Matrix => "standard monomials evaluated on points",
 	  "stds" => Matrix => "whose entries are the standard monomials",
 	  },
     "This function uses the Buchberger-Moeller algorithm to compute a the matrix ",
     TT "A", " in which the columns are indexed by standard monomials, the rows are
     indexed by points, and the entries are given by evaluation.  The ordering of
     the standard monomials is recorded in the matrix ", TT "stds", " which has a
     single column.
     Here is a simple
     example.",
     EXAMPLE lines ///
     
     ///,
     Caveat => "Program does not check that the points are distinct.",
     SeeAlso => {points},
     }

document {
     Key => {pointsByIntersection, (pointsByIntersection,Matrix,Ring)},
     Headline => "computes ideal of point set by intersecting maximal ideals",
     Usage => "pointsByIntersection(M,R)",
     Inputs => {
     	  "M" => Matrix => "in which each column consists of the coordinates of a point",
	  "R" => PolynomialRing => "coordinate ring of the affine space containing the points",
	  },
     Outputs => {
 	  List => "grobner basis for ideal of a finite set of points",
 	  },
     "This function computes the ideal of a finite set of points by intersecting
     the ideals for each point.  The coordinates of the points are the columns in
     the input matrix ", TT "M", ".",
     EXAMPLE lines ///
     M = random(ZZ^3, ZZ^5)
     R = QQ[x,y,z]
     pointsByIntersection(M,R)
     ///,
     SeeAlso => {points},
     }
document {
     Key => {FGLM,  (FGLM, GroebnerBasis, PolynomialRing, Option)},
       Headline => "Uses the FGLM algorithm to change a Groebner basis for a zero-dimensional ideal wrt to a monomial ordering mo1 to another 
     Groebner basis with respect to a monomial ordering mo2.",
     Usage => "G2 = points(std,G1,R,mo2)",
     Inputs => {
	  "G1" => GroebnerBasis => "A Groebner basis for the ideal wrt mo1", 
	  "R" => PolynomialRing => "The polynomial ring",
	  "mo2" => Option =>"The output monomial ordering"
	  },
     Outputs => { "S2" => PolynomialRing => "The polynomial ring where G2 lives",
	   	  "G2" => List => "The Groebner basis wrt to mo2"
		  },
     EXAMPLE lines ///
     n := 30
     m := 40;
     M = random(ZZ^n, ZZ^m);
     -- m points in QQ^n
     R = QQ[vars(0..(n-1))]
     --,MonomialOrder => GRevLex]
     --Compute a Gröbner basis for I(M) with respect to DegRevLex using the BM-algorithm
     timing ((Q,inG,Gd) = points(M,R);)
     DegRevLexGb = forceGB matrix {Gd};
     IR = ideal gens DegRevLexGb;
    --Convert the basis to a Lex-base using FGLM
    (S1,FGLMLexGb,QLex) = FGLM(DegRevLexGb, R, MonomialOrder => Lex);
    timing( (S1,FGLMLexGb,QLex) = FGLM(DegRevLexGb, R, MonomialOrder => Lex);)
     -- 2.44324 seconds
     -- Compute a Gröbner basis for I(M) with respect to Lex (in S) by
     -- using the BM-algorithm
     S2 = newRing(R, MonomialOrder => Lex)  
     timing((Q2,inG2,PointsLexGb) = points(M,S2);)
     --Map the result from FGLM (which is in S1) to S2
     S1toS2 = map(S2,S1);  
     FGLMLexGb = apply(FGLMLexGb, p -> S1toS2(p));
    --Check that they are equal (sort is used since "==" does not
    --apply for GB:s)
--FGLMLexGb
  --   sort FGLMLexGb
     gens forceGB matrix  {sort FGLMLexGb} == gens forceGB matrix {sort PointsLexGb}
--sort PointsLexGb
     -- true
     -- Now, to show that we gain speed, 
     -- compute a Lex Gröbner basis from the generators of IR.
     -- First map I from R to S2
     RtoS2 = map(S2,R);
     IS2 = ideal RtoS2 gens IR;
     timing (BuchbergerLex = gens gb IS2)
    -- 30.9826 seconds
     --Check that the result agrees with the FGLM result
     sort(BuchbergerLex) == gens forceGB matrix  {sort FGLMLexGb}
     -- true
     ///,
     SeeAlso => {points},
     }


TEST ///
R = ZZ/32003[vars(0..4), MonomialOrder=>Lex]
M = matrix(ZZ/32003,  {{0, -9, 4, -2, -4, -9, -10, 6, -8, 0}, 
            {1, 0, -10, 9, 3, -4, 1, 1, -10, -3}, 
	    {5, 7, -4, -5, -7, 7, 4, 6, -3, 2}, 
	    {2, 8, 6, -6, 4, 3, 8, -10, 7, 8}, 
	    {-9, -9, 0, 4, -3, 9, 4, 4, -4, -4}})
phi = makeRingMaps(M,R)
apply (gens(R),r->phi#2 r)
assert ( {4, -10, -4, 6, 0} == apply (gens(R),r->phi#2 r) )

J = pointsByIntersection(M,R);
C = points(M,R);
assert ( J == C_2 )
assert ( C_1 == ideal(e^6,d*e^3,d^2*e,d^3,c,b,a) )
assert ( C_0 == sort apply (standardPairs monomialIdeal C_2, p -> p#0) )
assert (
     (pointsMat(M,R))#0 == 
      matrix(ZZ/32003, {{1, -9, 81, -729, 6561, 4957, 2, -18, 162, 4}, {1, -9, 81, -729, 6561,
      4957, 8, -72, 648, 64}, {1, 0, 0, 0, 0, 0, 6, 0, 0, 36}, {1, 4, 16, 64, 256, 1024,
      -6, -24, -96, 36}, {1, -3, 9, -27, 81, -243, 4, -12, 36, 16}, {1, 9, 81, 729, 6561,
      -4957, 3, 27, 243, 9}, {1, 4, 16, 64, 256, 1024, 8, 32, 128, 64}, {1, 4, 16, 64,
      256, 1024, -10, -40, -160, 100}, {1, -4, 16, -64, 256, -1024, 7, -28, 112, 49}, {1,
      -4, 16, -64, 256, -1024, 8, -32, 128, 64}})
)
assert ( first entries transpose (pointsMat(M,R))#1 == C_0 )
///
end
toString C_1
restart
errorDepth = 0


uninstallPackage "Points"
installPackage "Points"
R = ZZ/32003[vars(0..4), MonomialOrder=>Lex]
M = matrix(ZZ/32003,  {{0, -9, 4, -2, -4, -9, -10, 6, -8, 0}, 
            {1, 0, -10, 9, 3, -4, 1, 1, -10, -3}, 
	    {5, 7, -4, -5, -7, 7, 4, 6, -3, 2}, 
	    {2, 8, 6, -6, 4, 3, 8, -10, 7, 8}, 
	    {-9, -9, 0, 4, -3, 9, 4, 4, -4, -4}})

phi = makeRingMaps(M,R)
apply (gens(R),r->phi#2 r)
assert ( {4, -10, -4, 6, 0} == apply (gens(R),r->phi#2 r) )


phi#2
time J = pointsByIntersection(M,R)
transpose matrix{oo}



time C = points(M,R)
transpose gens ideal C_2

M = random(ZZ^3, ZZ^5)
R = QQ[x,y,z]
phi = makeRingMaps(M,R)
apply (gens(R),r->phi#2 r)
phi#2

R = ZZ/32003[vars(0..4), MonomialOrder=>Lex]
M = random(ZZ^5, ZZ^150)

time J = pointsByIntersection(M,R);
transpose matrix{oo}

time C = points(M,R);
transpose gens ideal C_2
assert(J == C_2)

R = ZZ/32003[vars(0..4)]

K = ZZ/32003
R = K[vars(0..7), MonomialOrder=>Lex]
R = K[vars(0..7)]
M = random(K^8, K^500)
time C = points(M,R);
time J = pointsByIntersection(M,R);
assert(C_2 == J)

K = ZZ/32003
R = K[x_0 .. x_39]
M = random(K^40, K^80)
time C = points(M,R);


getColumnChange oo_0
apply(Fs, f -> f(a*b*c*d))
B = sort basis(0,2,R)
B = sum(flatten entries basis(0,2,R))
B = matrix{reverse terms B}
P = transpose matrix {apply(Fs, f -> f (transpose B))}
B * syz 
transpose oo
 -- column reduction:

P = mutableMatrix P 
H = new MutableHashTable
reduceColumn(P,null,H,0)
reduceColumn(P,null,H,1)
P
reduceColumn(P,null,H,2)
reduceColumn(P,null,H,3)
reduceColumn(P,null,H,4)
reduceColumn(P,null,H,5)
reduceColumn(P,null,H,6)
reduceColumn(P,null,H,7)
reduceColumn(P,null,H,8)
reduceColumn(P,null,H,9)
P
reduceColumn(P,null,H,10)
reduceColumn(P,null,H,11)
reduceColumn(P,null,H,12)
P

M = matrix{{1,2,3,4}}

K = ZZ/32003
M ** K

-- Local Variables:
-- compile-command: "make -C $M2BUILDDIR/Macaulay2/packages PACKAGES=Points pre-install"
-- End:
