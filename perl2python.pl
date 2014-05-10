#!/usr/bin/perl -w

# written by hjc.gibbs@gmail.com September 2013
# This script converts a perl script to a python script

# We begin by declaring a number of methods to store various pieces of information
# %variables is indexed by names and returns whether the variable is a hash, string,
# scalar or an array.
# @codeBlockLengths returns the length of the nth codeBlock

%variables = ();
$codeBlockCounter = 0;
@codeBlockLength = (); 

@perlCode = <>;

if ($perlCode[0] =~ /^#!/) {
	# translate #! line 
	print "#!/usr/bin/python2.7 -u\n";
	shift @perlCode;
}

# The following loop breaks code up into a number of loops
# The breaking of code into blocks is done greedily (So nested ifs and loops are initially ignored)

$i = 0;

while ($i < @perlCode) {
    if ($perlCode[$i] =~ /\n;/) {
         # Matches a single line statement
         $codeBlockLength[$codeBlockCounter] = 1;
         $codeBlockCounter += 1;
    } elsif ($perlCode[$i] =~ /^\s*#/ || $perlCode[$i] =~ /^\s*$/) {
         $codeBlockLength[$codeBlockCounter] = 1;
         $codeBlockCounter += 1;       
    } elsif ($perlCode[$i] =~ /(^\s*|\W)if\W/) {
         # Matches a if statement and then seeks the end of the code block
         $Numlines = 0;
         $OpenBrackets = 0; 
         
         # This is done once outside the loop incase the statement is only on one line.
         $OpenBrackets += $perlCode[$i] =~ /\{/; 
         $OpenBrackets -= $perlCode[$i] =~ /\}/;
         $Numlines ++;

         
         while ($OpenBrackets != 0) { 
             $OpenBrackets -= $perlCode[$i + $Numlines] =~ /\}/;
             $OpenBrackets += $perlCode[$i + $Numlines] =~ /\{/; 
             $Numlines ++;
         }
         
         $codeBlockLength[$codeBlockCounter] = $Numlines;
         $i += $Numlines;
         $i --;
         
         $codeBlockCounter ++; 
    } elsif ($perlCode[$i] =~ /(^\s*|\W)(while|for|foreach)\W/) {
         # Matches a while statement and then seeks the end of the code block
         $Numlines = 0;
         $OpenBrackets = 0; 
         
         # This is done once outside the loop incase the statement is only on one line.
         $OpenBrackets += $perlCode[$i] =~ /\{/; 
         $OpenBrackets -= $perlCode[$i] =~ /\}/;
         $Numlines ++;
         
         while ($OpenBrackets != 0) { 
             $OpenBrackets -= $perlCode[$i + $Numlines] =~ /\}/;
             $OpenBrackets += $perlCode[$i + $Numlines] =~ /\{/; 
             $Numlines ++;
         }
         
         $codeBlockLength[$codeBlockCounter] = $Numlines;

         $i += $Numlines;
         $i --;
         
         $codeBlockCounter ++; 
    } else {
         $codeBlockLength[$codeBlockCounter] = 1;
         $codeBlockCounter ++;  
    }
    $i ++;
}

# The next step is to scan the perl code for appropriate imports in the python code
# The variety of imports is limited at the moment but will be expanded later

%import = ();

foreach $line (@perlCode){
    if ($line =~ /ARGV/) {
        $import{'sys'} = 1;
    } elsif ($line =~ /\<STDIN\>/) {
        $import{'sys'} = 1;
    } elsif ($line =~ /\<\>/ ) {
        # http://stackoverflow.com/questions/1450393/how-do-you-read-from-stdin-in-python
        $import{'fileinput'} = 1;
    } elsif ($line =~ /((?:"[^"]+"|[^~]+)*)(?:[~]\s*)/) {
        $import{'re'} = 1;
    } elsif ($line =~ /split\s*\(\s*\//) {
        $import{'re'} = 1;
    }
}

foreach $key (keys %import) {
    print "import $key\n";
}

# The following loop will convert each code block
# Nested loops or ifs are translated recursively

$currentLine = 0;
$j = 0;

# Translate each block of code, incrementing by 1 for each code block 
# while keeping track of the line number

while ($j < $codeBlockCounter) {
    if ($codeBlockLength[$j] == 1) {
        # If the block is one-line then translate it using convertLine
        convertLine($currentLine); 
    } else {
        # If the block is multi-line then translate it using convertBlock
        convertBlock($currentLine, $codeBlockLength[$j]);
    }
    $currentLine += $codeBlockLength[$j];
    $j ++; 
}


sub convertBlock {
    my $start = $_[0];
    my $length = $_[1];
    
    # The type of code block is determined and then converted appropriately.
    # Since conversion is done recursively, the function is passed the
    # current level of indentation.
    
    if ($perlCode[$start] =~ /(^\s*|\W)if\W/) {

        convertIfBlock($start, $length, 0);
        
    } elsif ($perlCode[$start] =~ /(^\s*|\W)(while|foreach|for)\W/) {
        
        convertLoopBlock($start, $length, 0);
        
    } else {
        # print block as comments
        my $i;
        for($i = 0; $i < $length; $i ++) {
            print "# $perlCode[$start + $i]\n";
        }
    }
}

sub convertLoopBlock {
    my $startPoint = $_[0];
    my $endPoint = $_[1] + $_[0];
    my $current = $startPoint;
    my $currIndent = $_[2];
    my $line = $perlCode[$current];
    my $end;
    if ($line =~ /^\s*while\s*\((.*)\)\s*\{/) {
        printIdentation($currIndent);
        my $temp = $1;
        if ($temp =~ /\s*(\$\w*).*?=\s*(\<.*?\>)/) {
            print "for ".convertVariables($1)." in ".convertExpr($2).":\n";
        } else {
            # Incase loop is of form "while ($line = <F>)" for some arbitrary stream.
            print "while ", convertBoolean($temp), ":\n";
        }

        $current ++;
        
    } elsif ($line =~ /^\s*for\s*\(([^;]*);([^;]*);(.*)\)\s*/){
        printIdentation($currIndent);
        print convertExpr($1), "\n";
        printIdentation($currIndent);
        print "while ", convertBoolean($2), ":\n";
        # We save the third part of the for loop for printing at the end of the loop
        $end = convertExpr($3);
        $current ++;
    } elsif ($line =~ /^\s*foreach\s*(\$\w*)\s*\((.*)\)/) {
        
        print "for ", convertVariables($1), " in ", convertRange($2), ":\n";
        $current ++;
    }
    
    my $Numlines = 1;
    my $OpenBrackets = 0; 
    
    $currIndent ++;
    while ($current != $endPoint) {
        $line = $perlCode[$current];
        $Numlines = 1;
        $OpenBrackets = 0; 
        
        if ($line =~ /\Wif\W/) {
            # indicates nested if statement. To translate, the whole statement must be 
            # found and then translated with a higher indentation level by convertIfBlock
            
            # When number of open braces - number of closed braces = 0 the code block ends
            
            $OpenBrackets += $line =~ /\{/; 
            $OpenBrackets -= $line =~ /\}/;
            
            while ($OpenBrackets != 0) { 
                $OpenBrackets -= $perlCode[$current + $Numlines] =~ /\}/;
                $OpenBrackets += $perlCode[$current + $Numlines] =~ /\{/; 
                $Numlines ++;
            } 
            
            convertIfBlock($current, $Numlines, $currIndent);
            
        } elsif ($line =~ /(^\s*|\W)(while|for|foreach)\W/){ 
            # indicates nested loop. To translate, the whole statement must be 
            # found and then translated with a higher indentation level by convertLoopBlock
            
            $OpenBrackets += $line =~ /\{/; 
            $OpenBrackets -= $line =~ /\}/;
            
            while ($OpenBrackets != 0) { 
                $OpenBrackets -= $perlCode[$current + $Numlines] =~ /\}/;
                $OpenBrackets += $perlCode[$current + $Numlines] =~ /\{/;
                $Numlines ++;
            } 
            convertLoopBlock($current, $Numlines, $currIndent);
            
        } elsif ($line =~ /^\s*\}\s*$/) {
        
        } else {
            printIdentation($currIndent);
            convertLine($current);
        }
        $current += $Numlines;
    }
    
    if (defined $end) {
        printIdentation($currIndent);
        print $end, "\n";
    }
}

sub convertIfBlock {
    my $startPoint = $_[0];
    my $endPoint = $_[1] + $_[0];
    my $current = $startPoint;
    my $currIndent = $_[2];
    my $line = $perlCode[$current];
    # Start by handling the line with the if statement, then 
    printIdentation($currIndent);
    if ($line =~ /^\s*if\s*\((.*)\)\s*\{/) {
         print "if ", convertBoolean($1), ":\n";
         $current ++;
    } else {
         # this handles things like:
         # $line = 4 if (x==4)
         $line =~ /^(.*)if\s*\((.*)\)\s*/;
         print "if ".convertBoolean($2).":\n";
         printIndentation($currIndent + 1);
         print convertLine($1)."\n";
         return;
    }
    my $Numlines = 1;
    my $OpenBrackets = 0; 
    
    $currIndent ++;
    
    while ($current != $endPoint) {
        $line = $perlCode[$current];
        $Numlines = 1;
        $OpenBrackets = 0; 
        
        if ($line =~ /\s*elsif\s*\((.*)\)\s*\{/){

            printIdentation($currIndent-1);
            print "elif ", convertBoolean($1), ":\n";
            
        } elsif ($line =~ /\s*else\W/) {
            printIdentation($currIndent-1);
            print "else :\n";
            
        } elsif ($line =~ /\Wif\W/) {
            # indicates nested if statement. To translate, the whole statement must be 
            # found and then translated with a higher indentation level by convertIfBlock
         
            $OpenBrackets += $line =~ /\{/; 
            $OpenBrackets -= $line =~ /\}/;
            
            while ($OpenBrackets != 0) { 
                $OpenBrackets -= $perlCode[$current + $Numlines] =~ /\}/;
                $OpenBrackets += $perlCode[$current + $Numlines] =~ /\{/; 
                $Numlines ++;
            } 
            
            convertIfBlock($current, $Numlines, $currIndent);
            
        } elsif ($line =~ /(^\s*|\W)(while|for|foreach)\W/){ 
            # indicates nested loop. To translate, the whole statement must be 
            # found and then translated with a higher indentation level by convertLoopBlock
         
            $OpenBrackets += $line =~ /\{/; 
            $OpenBrackets -= $line =~ /\}/;
            
            while ($OpenBrackets != 0) { 
                $OpenBrackets -= $perlCode[$current + $Numlines] =~ /\}/;
                $OpenBrackets += $perlCode[$current + $Numlines] =~ /\{/; 
                $Numlines ++;
            } 
            
            convertLoopBlock($current, $Numlines, $currIndent);
            
        } elsif ($line =~ /^\s*\}\s*$/) {
        
        } else {
            printIdentation($currIndent);
            convertLine($current);
        }
        $current += $Numlines;
    }
    
}

sub printIdentation {
    # Given a level of indentation, prints the appropriate number of spaces.
    my $i = 0;
    my $max = 4*$_[0];
    while ($i<$max) {
        $i++;
        print ' ';
    }
}

sub extractVariables {
    my $arguments = $_[0];
    
    my @strings1 = $arguments =~ /\$[\w]*/g;
    foreach $var (@strings1){
        $var =~ s/^\$//;
        if (! defined $variables{$var} ) {
            # If the scalar is part of an array then add the array to variables hash
            if ($var =~ /(\w*)\[[^]]*\]/) {
                $variables{$1} = "Array";
            }
            $variables{$var} = "Scalar";
        }
    }
    
    my @strings2 = $arguments =~ /\@[\w]*/g;
    foreach $var (@strings2){
        $var =~ s/^\@//;
        if (! defined $variables{$var} ) {
            $variables{$var} = "Array";
        }
    }
    return (\@strings1, \@strings2);
}

sub convertVariablesForPrinting {
    my $line = $_[0];
    my @formatList = ();
    
    my ($scalar, $arrays) = extractVariables($_[0]);
    
    push(@$scalar, @$arrays);
    foreach $var (@$scalar) {
        if ($variables{$var} eq "Scalar"){
            $line =~ s/\$($var)/\{\}/;
        } elsif ($variables{$var} eq "Array"){
            $line =~ s/\@($var)/\{\}/;
        } else {
            next;
        }
        push(@formatList, $var);
    }
    
    $line = $line.".format(str(".join(') , str( ', @formatList)."))" if (@formatList);
    $line =~ s/\@ARGV/sys.argv\[1:\]/g;
    return $line;
}

sub convertVariables {
    my $line = $_[0];

    $line =~ s/\@ARGV/sys.argv\[1:\]/g;
    my ($scalar, $arrays) = extractVariables($_[0]);
    
    foreach $var (@$scalar) {
        $line =~ s/\$$var/$var/g;
    }
    foreach $var (@$arrays) {
        $line =~ s/\@$var/$var/g;
    }
    
    return $line;
}

sub convertLine {
    # Convert a single line of perl. 
    # A number of functions are called, depending on the case.
    
    my $line = $perlCode[$_[0]];
    
    if ($line =~ /^\s*#/ || $line =~ /^\s*$/) {
    
		# Blank & comment lines can be passed unchanged
	    print $line;
	    
	} elsif ($line =~ /^\s*print\s*(.*)[\s;]*$/) {
	    # This code handles print statements.
        # Unfortunately this will not handle single quotes or the use of a period
        # to concatenate strings in perl yet.
             
		@toPrint = convertPrintExpr($1);
		# if the last character is a newline it must remove the newline as python 
		# adds newlines automatically else the last print must be followed by a comma
		print "print ";
		if ($toPrint[@toPrint-1] =~ /\\n\s*\"/) {
            $toPrint[@toPrint-1] =~ s/\\n\s*\"(|\.format\()/\"$1/;
            pop (@toPrint) if ($toPrint[@toPrint-1] =~ /\"\"/);
            print join(',', @toPrint);
        } else {
            print join(',', @toPrint);
            print ',';
        }
        print "\n";
		     
	} elsif ($line =~ /\s*(\$|@)([\w]*)/){
	
		# This takes a single line, such as a declaration or some arithmetic, and
		# converts it to python.     
        print convertExpr($line), "\n";
        
    } elsif ($line =~ /(^\s*|\W)(last|next)/) {
    
        # Needs some fixing up
        $line =~ s/last/break/;
        $line =~ s/next/continue/;
        $line =~ s/;\s*$//;
        $line =~ s/^\s*//;
        print "$line\n"
    
    } else {
    
	     # Lines we can't translate is turned into comments
	     print "#$line\n";
	}
}

sub convertPrintExpr {
    # This function takes a print statement and splits it into a number of sub-statements
    # The splitting is done on non double quoted commas (via an amazing regex)
    # the statements are then individually converted into python.
    my $printExpr = $_[0];
    my @statements = ();
    my @convertStatements = ();
    my $expr;
    
    # Firstly the expression is split on any commas not surrounded by double quotes
    
    $printExpr =~ s/;\s*$//;
    while (length($printExpr)){
        $printExpr =~ s/^\s*//;
        
        if ($printExpr =~ s/^(chomp|split|join)\(([^\)]*?)\)(,)?//) {
            # As function calls can have commas which aren't surrounded by
            # double quotes, we have to explicitly handle this case.
            $expr = "$1($2)";
        } else {
            $printExpr =~ s/((?:"[^"]+"|[^,]+)*)(?:,\s*)?//; # This is Magic, don't touch
            $expr = $1;
        }
        push(@statements, $expr);
        
    }
    
    # Each expression is then converted, depending on whether they are quoted or not.
    
    my $i = 0;
    my $j = 0;
    my $newExpr;
    
    my @tempArray = ();
    
    while ($i < @statements){
        splice(@tempArray);
        while (length($statements[$i])){
            $statements[$i] =~ s/^\s*//;
            
            if ($statements[$i] =~ s/^(chomp|split|join)\(([^\)]*?)\)(\.)?//) {

                $expr = convertFunc("$1($2)");
                
            } else {
                $statements[$i] =~ s/("[^"]+"|[^.]*)(?:[.]\s*)?//; # Well I touched it.
                $expr = $1;
                $expr =~ s/\.$//;
            }
            push(@tempArray, $expr); 
        }
        
        for ($j = 0; $j < @tempArray; $j ++) {
            
            if ($tempArray[$j] =~ /\"/){ 
                $tempArray[$j] = convertVariablesForPrinting($tempArray[$j]);
            } elsif ($tempArray[$j] =~ /(!|=)~/) {
                $tempArray[$j] = convertRegex($tempArray[$j]);
            } else {
                $tempArray[$j] = convertVariables($tempArray[$j]);
            }      
            
        }
        
        $newExpr = join('+',@tempArray);
        push(@convertStatements, $newExpr) if ($newExpr ne "" and $newExpr ne ";");
        $i ++;
    }
    
    return @convertStatements;
}

sub convertExpr {
    my $expr = $_[0];
    my $temp;
    my @concatenationArray = ();
    
    if ($expr =~ /(!|=)~/) {
	    # This code handles Regular expressions
	    return convertRegex($expr);
    }
    
    while (length($expr)) {
        if ($expr =~ s/^(chomp|split|join)\(([^\)]*?)\)(\.)?//) {
            $temp = "$1($2)";
            
        } else {
            $expr =~ s/("[^"]+"|[^.]*)(?:[.]\s*)?//; # Well I touched it.
            $temp = $1;
            $temp =~ s/\.$//;
        }
        push(@concatenationArray, $temp);
    }
    
    my @tempArray;
    
    foreach $partition (@concatenationArray){
    
        $partition =~ s/\<STDIN\>/sys.stdin.read()/g;
        $partition =~ s/\<\>/fileinput.input()/g;
    
        # Expressions can take on two forms: quoted or unquoted
        # Quoted expressions have to be converted twice.
        if ($partition =~ /(\$|\@)(\w*)([^"]*)\"(.*)\"/){
            my ($temp1, $temp2, $temp3, $temp4) = ($1, $2, $3, $4);
            if ($temp3 =~ /\.=/){
                $partition = convertVariables("$temp1$temp2")." = ".convertVariables("$temp1$temp2")."+".convertVariablesForPrinting("\"$temp4\"");
            } else {
                $partition = convertVariables("$temp1$temp2").$temp3.convertVariablesForPrinting("\"$temp4\"");
            }
        
        } elsif ($partition =~ /(^\s*|\W)(last|next)/) {
            $partition = convertVariables($partition);
            $partition =~ s/last/break/;
            $partition =~ s/next/continue/;
    
        } elsif ($partition =~ /^\s*([$@\w]*)(\W*)(chomp|join|split)\s*\((.*)\);/) {
        
            if ($1 ne "" and $2 ne "") {
                $partition = convertVariables($1)." $2 ".convertFunc($3.$4);
            } else {
                $partition = convertVariables($4)." = ".convertFunc($3.$4);
            }
        
        } else {
            $partition = convertVariables($partition);

            if ($partition =~ /\s*(\w*)\s*(\+|-)(\+|-)\s*/) {
                $partition = "$1 $2= 1";
            }
        }
        push(@tempArray, $partition) if ($partition !~ /^\s*;\s*$/);
        
    }
    
    $expr = join('+', @tempArray);
    
    $expr =~ s/;\s*$//;
    $expr =~ s/^\s*//;
    
    return $expr;
}

sub convertBoolean {
    # This will translate boolean expressions but does not properly handle precedence
    my $statement = $_[0];
    $statement = convertVariables($statement);
    
    # change '&&' to 'and' and '||' to 'or'
    $statement =~ s/&&/and/g;
    $statement =~ s/\|\|/or/g;
    $statement =~ s/(\W)eq/$1==/g;
    $statement =~ s/(\W)ne/$1!=/g;
    
    my @temp2;
    my ($i, $j);
    my @temp1 = split (/\Wand\W/, $statement);
    
    # Each expression in the conditional is converted individually so the conditional
    # is split on all occurrences of 'and' and 'or'.
    
    for($i = 0; $i < @temp1; $i ++){
        splice(@temp2);
        @temp2 = split (/\Wor\W/, $temp1[$i]);
        for ($j = 0; $j < @temp2; $j ++) {
            $temp2[$j] = convertExpr($temp2[$j]);
        }
        $temp1[$i] = join (' or ', @temp2);
    }
    
    $statement = join(' and ', @temp1);
    
    return $statement;
}

sub convertFunc {
    my $line = $_[0];

    if ($line =~ /^\s*chomp\W*\$(\w*)/) {
    
        $line = "\$$1.rstrip('\\n')";
        
    } elsif ($line =~ /^\s*join[^\w\']*\'([^']*)\'\W*\@(\w*)/) {
    
        $line = "\'$1\'.join(\@$2)"; 
        
    } elsif ($line =~ /^\s*split\W*\((\'.*\'|\/.*\/),(.*?)(|,.*)\)/) {
        my ($pattern, $string) = ($1, $2);
        my $count;
        if (defined $3) {
            $count = $3;
        }
        if ($pattern =~ /\s*\//) {
            $pattern =~ s/^\s*\///;
            $pattern =~ s/\/\s*$//;
            $line = "re.split(\'$pattern\',$string";
        } else {
            $line = "$string.split(".$pattern;
        }
        
        $line .= ", $count" if ($count ne "");
        $line .= ")";
    }
    return convertVariables($line);
    
}

sub convertRange {
    my $range = $_[0];
    my @rangeList = ();
    my $counter = 0;
    my $temp;
    
    
    while (length($range)){
        $range =~ s/^\s*//;
        
        if ($range =~ s/^(chomp|split|join)\(([^\)]*?)\),?//) {
            # As function calls can have commas which aren't surrounded by
            # double quotes, we have to explicitly handle this case.
            $temp = "$1($2)";
        } else {
            $range =~ s/(\([^)]+\)|[^,]+)(?:,\s*)?//; # This is Magic, don't touch
            $temp = $1;
        }
        
        $rangeList[$counter] = $temp;#=~ s/,$//;
        $counter ++;
    }
    
    my $i = 0;
    for($i = 0; $i < @rangeList; $i++) {
        if ($rangeList[$i] =~ /^(.*)\.\.(.*)/) {
            $rangeList[$i] = "range($1, $2)"
        } elsif ($rangeList[$i] =~ /^(chomp|split|join)(\(.*\))/) {
            $rangeList[$i] = convertFunc("$1($2)");
        } else {
            $rangeList[$i] = convertVariables($rangeList[$i]);
        }
    }
    
    
    
    return join(', ', @rangeList);
}

sub convertRegex {
    my $line = $_[0];
    my $flags = "";
    my $result;
    
    if ($line =~ /^\s*(\$\w*)\s*=~\s*s\/(.*?)\/(.*?)\/(\w*);/){
        $result = convertVariables($1)." = re.sub(r\'$2\', \"$3\", ".convertVariables($1);
        $flags = $4;
    } elsif ($line =~ /^\s*(\$\w*)\s*=~\s*\/(.*?)\/(\w*)/) {
        $result = "re.search(r\'$2\', ".convertVariables($1);
        $flags = $3;
    } elsif ($line =~ /^\s*([\$\@]\w*)\s*=\s*(\$\w*)\s*=~\s*\/(.*?)\/(\w*);/) {
        $result = convertVariables($1)." = re.search(r\'$3\', ".convertVariables($2);
        $flags = $4;
    } else  {
        $result = "#".$line;
    }
    
    #if ($flags =~ /(m|i|g)/){
    #    $result .= ", ";
    #    foreach $letter ('M','I','G') {
    #        if ($flags =~ /$letter/i) {
    #            $result .= "re.$letter|"
    #        }
    #    }  
    #    $result =~ s/\|\s*$//;
    #    $result .= ")";   
    #}
    
    $result .= ")";
    
    $result =~ s/\<STDIN\>/sys.stdin.read()/g;
    $result =~ s/\<\>/fileinput.input()/g;
    
    return $result;
}
