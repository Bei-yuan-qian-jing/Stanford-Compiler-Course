
/*
 *  The scanner definition for COOL.
 */

/*
 *  Stuff enclosed in %{ %} in the first section is copied verbatim to the
 *  output, so headers and global definitions are placed here to be visible
 * to the code in the file.  Don't remove anything that was here initially
 */

%{

#include <cool-parse.h>
#include <stringtab.h>
#include <utilities.h>

/* The compiler assumes these identifiers. */
#define yylval cool_yylval
#define yylex  cool_yylex

/* Max size of string constants */
#define MAX_STR_CONST 1025
#define YY_NO_UNPUT   /* keep g++ happy */

extern FILE *fin; /* we read from this file */

/* define YY_INPUT so we read from the FILE fin:
 * This change makes it possible to use this scanner in
 * the Cool compiler.
 */

#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) \
	if ( (result = fread( (char*)buf, sizeof(char), max_size, fin)) < 0) \
		YY_FATAL_ERROR( "read() in flex scanner failed");

 /* to assemble string constants */
char string_buf[MAX_STR_CONST];

 /* pointer points to the end of the string_buf */
char *string_buf_ptr;


 /* the current line_number */
extern int curr_lineno;
extern int verbose_flag;

extern YYSTYPE cool_yylval;

/*
 *  Add Your own definitions here
 */

 /* the depth of the nested comment */
int comment_depth = 0;

 /* we can meet multiple errors in one string. 
  * We use this flag to record whether the current error is the first meeted error.
  * If we meet the error like the "\0", EOF, "\n", 
  * we need to return to INITIAL immediately and report the error.
  * Other errors should be record if they are the first error met in the string, 
  * otherwise they are not recorded. 
  */
bool first_meet_an_error_in_str = true;

 /* check whether the length of the string is beyond the max value, do not consider the "\0" at the end */
 /* If there is a lenght error and it is the first error in the string, collect the error message */
 /* do not return the ERROR immediately. */
 /* If there is a length, the function return true; */
bool check_str_len();

%}

 /* the condition environment */
%x COMMENT SINGLE_COMMENT
%x STRING


/*
 * Define names for regular expressions here.
 */

 /*
  * Keywords are case-insensitive except for the values true and false,
  * which must begin with a lower-case letter.
  */
CLASS		(?i:class)
ELSE		(?i:else)
FI		(?i:fi)
IF		(?i:if)
IN		(?i:IN)
INHERITS	(?i:inherits)
ISVOID		(?i:isvoid)
LET		(?i:let)
LOOP		(?i:loop)
POOL		(?i:pool)
THEN		(?i:then)
WHILE		(?i:while)
CASE		(?i:case)
ESAC		(?i:esac)
NEW		(?i:new)
OF		(?i:of)
NOT		(?i:not)


/*
 * let the "_"to be the special leter
 */
LETTER      [a-zA-Z_]

/*
 * single digit
 */
DIGIT		[0-9]
NEWLINE		\n
WHITESPACE_NO_NEWLINE  [ \f\r\t\v] 	

/*
 *complex type
 */
INT_CONST	{DIGIT}+
TYPE_ID		[A-Z]({DIGIT}|{LETTER})*
OBJECT_ID	[a-z]({DIGIT}|{LETTER})*


%%


 /*
  *  Nested comments
  */

"*)" {
     cool_yylval.error_msg = "Unmatched closed comment";
     return ERROR;
}

"(*" {  BEGIN(COMMENT); comment_depth++; }

<COMMENT>{
	<<EOF>>		{ BEGIN(INITIAL); cool_yylval.error_msg = "EOF in a comment"; return (ERROR); }
	[^*()\n]*	{; } /* for character other than "*","(",")","\n", then eat up this character. */
	"*"		{; } /* eat up. */
	"("		{; }
	")"		{; }
	\n		{curr_lineno++; }
	"(*"		{comment_depth++; }
	"*)"		{if(--comment_depth == 0) BEGIN(INITIAL); }
}


 /*
  *  single comment
  */
"--" { BEGIN(SINGLE_COMMENT); }

<SINGLE_COMMENT>{
 /* EOF in single comment is not an error */
  <<EOF>>          { BEGIN(INITIAL); }
  [^\n]*	   {; }
  {NEWLINE}        { curr_lineno++; BEGIN(INITIAL);}
}


 /* begin the condition of STRING. */
 /* let the string_bug_ptr points to the head of the array string_buf */
 /*first_meet_an_error_in_str = true meas that do not meet an error in the string yet. */

\" { BEGIN(STRING); string_buf_ptr = string_buf; first_meet_an_error_in_str = true; }

<STRING>\" {
    BEGIN(INITIAL);
    // if we already record the error message, return the error directly.
    if(!first_meet_an_error_in_str)
	return ERROR;

    // if we get the length error, return this error.
    // note that, the "\0" at the end of the string do not need to be considered in length checking process
    check_str_len();
    if(!first_meet_an_error_in_str)
	return ERROR;

    // add an "\0" manually to the end of the string.
    *string_buf_ptr++ = '\0';
    // record the content of the string.
    cool_yylval.symbol = stringtable.add_string(string_buf);
    return STR_CONST;
}

 /* if we meet a EOF error, we need to return to the initial and return the error immediately. */
 /* but if the EOF error is not the fisrt error, then we do not need to record it as the error message. */
<STRING><<EOF>> {
    if(first_meet_an_error_in_str) {
        cool_yylval.error_msg = "EOF in string constant";
	first_meet_an_error_in_str = false;
    } 
    BEGIN(INITIAL);
    return ERROR;
}

 /* we need to put a "\" + "\n" at the end of each line in the multi-lined strings. */
<STRING>\\\n {
    curr_lineno++;
    /* there are still some empty positions in the array */
    if(!check_str_len())
	 *string_buf_ptr++ = '\n';
}

 /* this error need to be returned immediately. */
<STRING>\n {
    if(first_meet_an_error_in_str){
	 cool_yylval.error_msg = "Unterminated string constant";
	 first_meet_an_error_in_str = false;
    }
    curr_lineno++;
    BEGIN(INITIAL);
    return ERROR;
}

  /* meet a null in the string */
<STRING>\0|\\\0 {
    if(first_meet_an_error_in_str){
	cool_yylval.error_msg = "String contains null character";
	first_meet_an_error_in_str = false;
    }
}

 /*
  *  String constants (C syntax)
  *  Escape sequence \c is accepted for all characters c. Except for 
  *  \n \t \b \f, the result is c.
  *
  */

 /* only if there is some empty position in the array, we push the character into the array. */
<STRING>\\[^ntbf] {
    if(!check_str_len())
        *string_buf_ptr++ = yytext[1];
}
	
<STRING>\\b {
    if(!check_str_len())
	 *string_buf_ptr++ = '\b';
}    

<STRING>\\t {
    if(!check_str_len())
	*string_buf_ptr++ = '\t';
}

<STRING>\\n  {
    if(!check_str_len())
	*string_buf_ptr++ = '\n';
}

<STRING>\\f {
    if(!check_str_len())
	*string_buf_ptr++ = '\f';
}

 /* all the characters other then nweline will be add the string directly. */
<STRING>. {
    if(!check_str_len())
	*string_buf_ptr++ = *yytext;
}

 /*
  *  The single-character operators.
  */
"~"		{return '~'; }
"@"		{return '@'; }
"*"		{return '*'; }
"("		{return '('; }
")"		{return ')'; }
"-"		{return '-'; }
"+"		{return '+'; }
"<"		{return '<'; }
"="		{return '='; }
"{"		{return '{'; }
"}"		{return '}'; }
":"		{return ':'; }
";"		{return ';'; }
","		{return ','; }
"/"		{return '/'; }
"."		{return '.'; }


 /*
  *  The multiple-character operators.
  */
"=>"		{return DARROW; }
"<="		{return LE; }
"<-"		{return ASSIGN; }

 /*
  * Keywords are case-insensitive except for the values true and false,
  * which must begin with a lower-case letter.
  */
{CLASS}		{return CLASS; }
{ELSE}		{return ELSE; }
{FI}		{return FI; }
{IF}		{return IF; }
{IN}		{return IN; }
{INHERITS}	{return INHERITS;}
{ISVOID}	{return ISVOID; }
{LET}		{return LET; }
{LOOP}		{return LOOP; }
{POOL}		{return POOL; }
{THEN}		{return THEN; }
{WHILE}		{return WHILE; }
{CASE}		{return CASE; }
{ESAC}		{return ESAC; }
{NEW}		{return NEW; }
{OF}		{return OF; }
{NOT}		{return NOT; }

t[Rr][Uu][Ee]           { cool_yylval.boolean = 1; return (BOOL_CONST); }
f[Aa][Ll][Ss][Ee]       { cool_yylval.boolean = 0; return (BOOL_CONST); }


{INT_CONST} {
    cool_yylval.symbol = inttable.add_string(yytext); 
    return INT_CONST;
}

{TYPE_ID} {
    cool_yylval.symbol = inttable.add_string(yytext); 
    return TYPEID;
}

{OBJECT_ID} {
    cool_yylval.symbol = inttable.add_string(yytext); 
    return OBJECTID;
}

{WHITESPACE_NO_NEWLINE}+ {; } /* Eat up all the  whitespaces */
{NEWLINE} {curr_lineno++;}


.   { cool_yylval.error_msg = yytext; return (ERROR); }

%%


bool check_str_len(){
     /* if the flag is 1, it means that there is a length error. */
     int flag = 0;
     /* only record the error message when there is a length error and the error is first met */
     if(string_buf_ptr - string_buf + 1 > MAX_STR_CONST && first_meet_an_error_in_str){
          cool_yylval.error_msg = "String constant too long";
	  first_meet_an_error_in_str = false;
     }
     
     if(string_buf_ptr - string_buf + 1 > MAX_STR_CONST)
         return true;
     return false;
}
