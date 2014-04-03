#!/usr/bin/perl -w
use utf8;
use strict;	# impose a little discipline :P
use warnings;
use MARC::Batch;	#~ use MARC::Record;	#~ use MARC::Field;
use File::Basename;
use Getopt::Long;
use open qw/:std :utf8/;	#sets STDOUT, STDIN BIBLIONUMBER_OFFSET& STDERR to use UTF-8....
use Marcgyver;  # import default list of items.
use POSIX 'strftime';
use Locale::Language;
use Text::CSV_XS;	# Useful: http://perlmaven.com/how-to-read-a-csv-file-using-perl # INSTALL Text::CSV_XS !!! # Others: DBD::CSV (DBI will load DBD::CSV), like SQL; Text::CSV::Slurp
	#~ http://search.cpan.org/~jzucker/DBD-RAM-0.072/RAM.pm#Creating_in-memory_tables_from_data_and_files:_import%28%29
	#~ http://perlmaven.com/calculate-bank-balance-take-two-dbd-csv
use Data::Dumper;	# For debug purpose only; print Dumper($MarcRecord);
use Term::ProgressBar::Simple;	# sudo perl -MCPAN -e 'install Term::ProgressBar::Simple'

#CONFIGURATION
use constant {	# Ref: http://perldoc.perl.org/constant.html
	DEBUG => 0,
	BIBLIONUMBER_OFFSET => 2147483647, # from  perl -MPOSIX -le'print for CHAR_MAX, INT_MAX, LONG_MAX, SHRT_MAX, UC+HAR_MAX, UINT_MAX, ULONG_MAX, USHRT_MAX'
	PROGRESS => 0,
	FULLMIG => 1,
	ZIPONLOCALFIELD => 1.	# 0=False
};
my $marcorgcode ="AR-BaUFI";  	# Indique aqui su código marc. Puede obtenerlo en http://www.loc.gov/marc/organizations/form-spa.html
my $subject_CSV_file = "Tesauro-fiuba_-_terminos.csv";	# Origen: https://docs.google.com/spreadsheet/ccc?key=0Aj9d6Iij97_ndFAxVWxBQ21QcFJWMk5tM0xRR0NqZHc#gid=0
my $bookbinding_CSV_file = "Libros_de_Encuadernacion_-_LE.csv";	# Origen: smb://fs2fiuba/biblioteca/PT-Documentos%20Compartidos
my $oSuffix = "-mig";


#KNOWN BUGS
#~ Genero HTML para un registro pero con header y fin html como para todos los registros. Idem el resto.
#~ Doesn't die nicely when invalid input mrc file. MARC::Batch->new('USMARC', $input)

#NOTES
#~ Ejemplares, Holdings data fields (9xx):	http://wiki.koha-community.org/wiki/Holdings_data_fields_(9xx)
#~ INSTALAR
	#~ de CPAN XML::SAX XML::SAX::Expat (como dice http://search.cpan.org
	#~ de sf.net MARC::File::XML
#~ In all frameworks must be present 964 field (ZIPONLOCALFIELD)


sub usage {
	print 
		"\n    mig/1.0-dev - MARC migration/translation manipulation tool\n".
		"    http://www.pabloabianchi.com.ar/\n\n".
		"Usage: $0 [OPTIONS] MARC_FILE \n\n".
		"Options:\n".
		"  -o  --output=FILE           Output filename (by default append a suffix).\n".
		"  -of --output-format=FORMAT  Output format. Options are: MRC, HTML, TXT (see verbose option).\n".
		"  -n  --number=NUMBER         The NUMBER of records to work with. If missing, all the file processed.\n".
		"  -os --offset=NUMBER         File offset before importing, ie NUMBER of records to skip.\n".
		"  -v  --verbose=NUMBER        Verbose mode. 1 means \"some infos\", 2 means \"MARC dumping\".\n".
		"  -nl --no-logs               Avoid generating a .log file.\n".
		"  -h  --help                  This version/help screen.\n";
	exit;
}


#[OPTIONS]:
my $output;
my $outputFormat;
my $iNumber = 2147483647;	# perl -MPOSIX -le 'print LONG_MAX'
my $iOffset = 0;
my $verbose;
my $noLOGs;
my $help;
GetOptions(
	'o|output=s' => \$output,	# ToDo
	'of|output-format=s' => \$outputFormat,	# ToDo
	'n|number=s' => \$iNumber,
	'os|offset=s' => \$iOffset,
	'v|verbose=i' => \$verbose,	# ToDo
	'nl|no-logs=s' => \$noLOGs,	# ToDo
	'h|help' => \$help,
) or die "Incorrect usage!\n";

if ( @ARGV eq 0 or defined $help) {
	usage ();
	exit 0;
}

my $input = $ARGV[$#ARGV] or die "Usage: $0 [OPTIONS] INPUT_MARC_FILE \n";
(my $name, my $path, my $suffix) = fileparse( $input, "\.[^.]*" );

$output = $name.$oSuffix.$suffix unless $output;

my $outputHTML = 	$name.$oSuffix.".html";
my $outputTXT = 	$name.$oSuffix.".txt";
my $outputLOG = 	$name.$oSuffix.".log";

binmode STDOUT, ':utf8';

open ( OUTPUTMRC, '> '.$output )  or die $!;
binmode OUTPUTMRC, ':utf8';
open ( OUTPUTHTML, '> '.$outputHTML )  or die $!;
binmode OUTPUTHTML, ':utf8';
open ( OUTPUTTXT, '> '.$outputTXT )  or die $!;
binmode OUTPUTTXT, ':utf8';
open ( OUTPUTLOG, '> '.$outputLOG )  or die $!;
binmode OUTPUTLOG, ':utf8';


#~ my $bookbinding_CSV = Text::CSV->new ({
	#~ binary => 1,
	#~ auto_diag => 1,
	#~ sep_char => ',' # not really needed as this is the default
#~ });
#~ 
#~ open ( my $bookbinding_CSV_fh, "<:encoding(utf8)", $bookbinding_CSV_file ) or die "$bookbinding_CSV_file: $!";

#~ my $fh = IO::File->new( 'gunzip -c marc.dat.gz |' );
my $irecs = MARC::Batch->new('USMARC', $input) or die "Invalid input file. ".$!;	# PRE: Expects UTF-8 input
#~ if ( ! $irecs->filename() ) { die $!; };	# or die usage()	# ERROR: Strange... why doesn't work now...?
#my $linter = MARC::Lint->new();
$irecs->strict_off();	# continue after it has encountered what it believes to be bad MARC data
$irecs->warnings_on();

#~ if (PROGRESS) { my $progress = Term::ProgressBar::Simple->new( countMARCRecords($irecs) ); }

my $count = 0;
while (my $irec = $irecs->next()) {
	$count++;	# ToDo: Use "continue {}"?
	#~ if (PROGRESS) { $progress++; }
	if ( $count < $iOffset ) { next; }	# If out of range: i<x0 OR i>=x0+d
	if ( $count > $iOffset+$iNumber ) { last; }	# If out of range: i<x0 OR i>=x0+d

	#~ if ( shouldBeTranslated($irec) ) {
	#~ if ( shouldBeTranslated($irec) and ( $irec->subfield( '911', 'a' ) =~ m/00003225/i ) ) {
	if ( shouldBeTranslated($irec) 
		#~ and (
			#~ ( $irec->subfield( '911', 'a' ) =~ m/^00000209$/i ) 
			#~ or
			#~ ( $irec->subfield( '911', 'a' ) =~ m/^00009104$/i ) 
			#~ or
			#~ ( $irec->subfield( '911', 'a' ) =~ m/^00001119$/i )
			#~ or
			#~ ( $irec->subfield( '911', 'a' ) =~ m/^00001842$/i )
		#~ )
	) {
		my $orec = translateBIBUN2MARC($irec);
		#~ if ( 1 == 0 ) {
		#~ if ( 0 == 0 ) {
		#~ if ( length( $orec->field('008')->as_string() ) > 40 ) {
		#~ if (  $orec->subfield('650','a') or $irec->subfield('065','a') =~ m/ARGENTINA/i ) {
		#~ if (  $orec->subfield('260','a') ) {
		#~ if (  $irec->subfield('075','c') ) {
			#~ $irec = sortTAGs($irec);
			#~ print "\nINPUT ------------------------------------\n";
			#~ print "\n".$irec->as_formatted()."\n";
			#~ print "I: ".$irec->field('028')->as_formatted()."\n";

			#~ print "\nOUTPUT ------------------------------------\n";
			#~ print "\n".$orec->as_formatted()."\n";
			#~ print "I: ".$irec->field('045')->as_formatted()."\n";
			#~ print "O: ".$orec->field('260')->as_formatted()."\n";

			print "#".$count." ";	# COUNT
			#~ print $count." - ".$orec->field('001')->as_formatted()."\n";
		#~ }

		#~ print $orec->field('008')->as_string()."\n";

		#~ if ( length($f008) <= 40 ) {}
		
		# OUTPUTS:
		print OUTPUTMRC $orec->as_usmarc();
		#~ print OUTPUTHTML print2html($irec, $orec);
		print OUTPUTTXT print2txt($orec, "openisis");	# ToDo: open and close
	}
}

if ( my @warnings = $irecs->warnings() ) {
	print "\nWarnings were detected!\n", @warnings;
	#~ warn "\nWarnings encountered while processing ISO-2709 record with title \"".$irecs->title()."\":\n";
	#~ foreach my $warn (@warnings) { warn "\t".$warn };
}

close(OUTPUTMRC);
#~ close(OUTPUTHTML);
#~ close(OUTPUTTXT);
#~ close $bookbinding_CSV_fh,;

exit 0;

sub shouldBeTranslated {	# For BIBUN
	my $iRec = shift;
	
	my $input_field_005 = 915;
	my $input_field_007 = 917;
	my $input_field_008 = 918;
	
	if (
		defined( $iRec->field('020') ) #	Analiticas
		|| defined( $iRec->field('040') )	# Reuniones
		|| defined( $iRec->field('015') )	# Revistas
		|| defined( $iRec->field('030') )	# Colecciones
		|| ( defined($iRec->subfield($input_field_008,'a')) && ('CD-ROM' ~~ uc($iRec->subfield($input_field_008,'a'))) )
		|| ( defined($iRec->subfield($input_field_007,'a')) && ('TRABPROF' ~~ uc($iRec->subfield($input_field_007,'a'))) )
		|| ( defined($iRec->subfield($input_field_005,'a')) && ('S' ~~ uc($iRec->subfield($input_field_005,'a'))) )
		|| ( defined($iRec->subfield($input_field_007,'a')) && ('BECA' ~~ uc($iRec->subfield($input_field_007,'a'))) )
		|| ( defined($iRec->subfield($input_field_007,'a')) && ('FOTOCOPIA' ~~ uc($iRec->subfield($input_field_007,'a'))) )
		|| ( defined($iRec->subfield($input_field_007,'a')) && ('PRGESTU' ~~ uc($iRec->subfield($input_field_007,'a'))) )
		|| ( defined($iRec->subfield($input_field_007,'a')) && ('CATALOGO' ~~ uc($iRec->subfield($input_field_007,'a'))) )

		|| defined( $iRec->field('055') ) # THESIS			ACTIVA == GENERA TODO MENOS TESIS (CAMBIAR PREFFIX)
		#~ || !defined( $iRec->field('055') ) # NOT THESIS		ACTIVA == GENERA SOLO TESIS (CAMBIAR PREFFIX)
	) {
		return 0;
	} else {
		return 1;
	}
	return 1;	# This should be dead code...
}

sub getYears {
	# Recive a string with possible years of Publication years. Return an array of years (it could be 1999 or 19-?
	my $date = shift;
	my @dates_array = ();
	$date =~ s/^([\[cC]?)([0-9]{2})([\?\-0-9]{2}[\?]?)-([0-9]{2})$/$1$2$3-$2$4/gi;	# from c1937-38 a c1937-1938
	$date =~ s/c//g;	# Remove "c"
	$date =~ s/[\[\]]//g;	# Remove "[" and "]"
	$date =~ s/([0-9]{2}), ([0-9]{2})/$1-$2/g;	# "c1980, 1990" to "c1980-1990"
	my $date1 = lc($date);
	my $date2 = lc($date);
	if ( length ($date1) <= 8 ) {	# date have one year (probably)
		$date1 =~ s/[\-?]/u/g;	# Change "-" and "?" for "u"
		$date1 = substr($date1, 0, 4);
		push(@dates_array, $date1);
	} else {	# date have two years (probably)
		$date1 =~ s/[\-?]/u/g;
		$date1 = substr($date, 0, 4);
		$date2 =~ s/^.*-([^\-]*)$/$1/;	# Extract second date
		$date2 =~ s/[\-?]/u/g;	# Change "-" and "?" for "u"
		$date2 = substr($date2, 0, 4);
		push(@dates_array, $date1);
		push(@dates_array, $date2);
	}
#print scalar (@dates_array)."\t".$date."\t - \t".join( ' ~ ', @dates_array )."\n";
	return @dates_array;
}

sub subfields2array {	# From http://www.nntp.perl.org/group/perl.perl4lib/2010/09/msg2782.html
	# extract subfields as an array of array refs. where $field is a MARC::Field object
	# ie, convert MARC::Field object to @array ($code and $data alternally).
	my $field = shift;
	my @subfields = $field->subfields();
	my @newsubfields = ();
	while (my $subfield = pop(@subfields)) {
		my ($code, $data) = @$subfield;
		unshift (@newsubfields, $code, $data);
	}
	return @newsubfields;
}

sub updateFieldTag {
	my ($field, $newTag) = @_;
	$field->replace_with( new MARC::Field($newTag, $field->indicator(1), $field->indicator(2), subfields2array($field) ) );
	return $field;
}

sub translateISBN {
	my ($iRec, $oRec) = @_;
	
	my @fields = $iRec->field( '010' );
	foreach my $field ( @fields ) {
		my @outputSubfields = ();
		my $ISBN = $field->subfield('a');
		if ( $ISBN ) {
			push(@outputSubfields, 'a', $ISBN );
		}
		my $ISBN_invalid = $field->subfield('z');
		if ( $ISBN_invalid ) {
			push(@outputSubfields, 'z', $ISBN_invalid );
		}
		if ( @outputSubfields ) {
			my $newField = MARC::Field->new('020', '', '', @outputSubfields);
			$oRec->insert_fields_ordered( $newField );
		}
	}
	#~ (obra completa)
	my @iFields_011 = $iRec->field( '011' );
	foreach my $field ( @iFields_011 ) {
		my @outputSubfields = ();
		my $ISBN_ObraCompleta = $field->subfield('a');
		if ( $ISBN_ObraCompleta ) {
			push(@outputSubfields, 'a', $ISBN_ObraCompleta." (Obra completa)" );
		}
		if ( @outputSubfields ) {
			my $newField = MARC::Field->new('020', '', '', @outputSubfields);
			$oRec->insert_fields_ordered( $newField );
		}
	}
	return $oRec;
}

sub translateTitle {
	#~ 1º OCC del 24^t => 245$a
	#~ 2+º OCCs del 24^t => 246$a	# 246 Varying Form of Title (R)
	my ($iRec, $oRec) = @_;

	my $iFieldTag = '024';	# Monography title for input format
	my $iSubfieldCode = 't';	 # Just one of the used subfields ('s'..)
	#~ my $oTitle_Field = '245';
	#~ my $oTitle_VaryingForm_Field = '246';	# Varying Form of Title
	
	#~ if ( ! defined $iRec->field( $iFieldTag ) ) { return $oRec; }
	
	my @fields = $iRec->field( $iFieldTag );
	my $count = 0;
	foreach my $field ( @fields ) {

		my @outputSubfields = ();

		my $title = $field->subfield( $iSubfieldCode );


		if ( defined($title) and $title ne '' ) {	# if ( $subfield_data ) {	#	Unfortunately this will be false when $name = 0;

			my $subtitle = $field->subfield( 's' );	# 245 $b - Remainder of title (NR)  OR  $n - Number of part/section of a work (R)
			if ( $count == 0 ) {

				push(@outputSubfields, 'a', $title );

				#~ 245 - Title Statement (NR)
				#~ If exist 24^s && contiene (vol|part|...) al 'n' de la misma OCC, else to 'b'
				if ( defined( $subtitle ) and ($subtitle ne '') ) {
					if ( $subtitle =~ m/(part |parte |vol |volume |volumen |tomo |libro )/i ) {
						push(@outputSubfields, 'n', $subtitle );
					} else {
						push(@outputSubfields, 'b', $subtitle );
					}
				}
				my $statement_of_responsibility = $field->subfield( 'r' );	#  245 $c - Statement of responsibility, etc. (NR)
				if ( defined( $statement_of_responsibility ) and $statement_of_responsibility ne '' ) {
					$statement_of_responsibility =~ s/^\s+|\s+$//g;	# remove whitespace at the beginning or end
					push(@outputSubfields, 'c', $statement_of_responsibility );
				}
				

				if ( @outputSubfields ) {
					my $newField = MARC::Field->new('245', '0', getTitleSecondIndicator( $title ), @outputSubfields);
					
					# Add MARC 21 title punctuation
					if ( defined($newField->subfield('b')) and defined($newField->subfield('c')) ) {
						$newField->update( a => $newField->subfield('a')." : ", b => $newField->subfield('b')." / " );
					} elsif ( defined($newField->subfield('b')) and not defined($newField->subfield('c')) ) {
						$newField->update( a => $newField->subfield('a')." : " );
					} elsif ( not defined($newField->subfield('b')) and  defined($newField->subfield('c')) ) {
						$newField->update( a => $newField->subfield('a')." / " );
					}
					
					$oRec->insert_fields_ordered( $newField );
				}
			} else {
				if ( defined( $title ) and $title ne '' ) {
					push(@outputSubfields, 'a', $title );
				}
				#~ 246 - Varying Form of Title (R)
				if ( defined( $subtitle ) and $subtitle ne '' ) {
					push(@outputSubfields, 'b', " : ".$subtitle );
				}
				if ( @outputSubfields ) {
					my $newField = MARC::Field->new('246', '2', getTitleSecondIndicator( $title ), @outputSubfields);
					$oRec->insert_fields_ordered( $newField );
				}
			}
			$count++;
		}
	}

	# TITULO UNIFORME
	my $uniformTitle = $iRec->subfield('027','a');
	if ( $uniformTitle ) {
		my $newField = MARC::Field->new('240','0', getTitleSecondIndicator( $uniformTitle ) ,'a' => $uniformTitle);
		$oRec->insert_fields_ordered( $newField );
	}
	
	return $oRec;
}

sub cantNombresPersonalesSinFunc {	# Devuelve count(28[]), contando sólo los 28 sin ^f y uno de ellos debe ser primer occ
	my ($iRec) = @_;

	my $iPersonalNameTag = '028';
	my $iFunctionSubfieldCode = 'f';

	my $occ = 1;
	my $counter = 0;
	my @fields = $iRec->field( $iPersonalNameTag );
	foreach my $field ( @fields ) {
		# It counts only if doesn't have function AND (is the first occ, OR the second or more but the firstone hadn't function)
		if ( !defined($field->subfield( $iFunctionSubfieldCode )) and ( ( $occ == 1 ) or ($counter > 0) ) ) {
			$counter++;
		}
		$occ++;
	}
	return $counter;
}

sub cantNombresCorporativosSinFunc {
	my ($iRec) = @_;

	my $iCorporateName = '029';
	my $iFunctionSubfieldCode = 'f';

	my $occ = 1;
	my $counter = 0;
	my @fields = $iRec->field( $iCorporateName );
	foreach my $field ( @fields ) {
		if ( !defined($field->subfield( $iFunctionSubfieldCode )) and ( ( $occ == 1 ) or ($counter > 0) ) ) {	# It counts only if doesn't have function AND is the first occ, OR the second or more but the first one hadn't function
			$counter++;
		}
		$occ++;
	}
	return $counter;
}

#~ sub cantNombresReunion {	# Devuelve count(40[]^n)
#~ }

sub translateAuthor {
	my ($iRec, $oRec) = @_;
	my $iPersonalNameTag = '028';	# Personal name input field
	my $iCorporateNameTag = '029';	# Corporate name input field
	my $iFunctionSubfieldCode = 'f';	 # function of Author FOR PERSONAL AND CORPORATE NAMES
	my @newPersonalNames = ();
	my @newCorporateNames = ();

	#~ ES: ToDo: ¿Esta es la forma antigua de migrar campos?
	#~ ES: MEJOR, MIGRAR 28 A CAMPO GENÉRICO, 29 A CAMPO GENÉRICO, Y LUEGO REEMPLAZAR VALOR GENÉRICO POR EL QUE CORRESPONDA
	INPUT_FIELD_028: {	# PERSONAL_NAME
		my @inputPersonalNames = $iRec->field( $iPersonalNameTag );
		foreach my $field ( @inputPersonalNames ) {
			my $surname = $field->subfield('a');	# ES:"apellido"
			my $name = $field->subfield('b');
			if ( $surname ) { $surname =~ s/,//g; }	# Removes commas, if any...
			if ( $name ) { $name =~ s/,//g; }
			my $function = $field->subfield('f');
			my $date = $field->subfield('d');
			my $personal_name = "";
			if ( $surname and $name ) {
				$name =~ s/([A-Z])( |$)/$1. /g;
				$name =~ s/^\s+|\s+$//g;	# Trim
				$personal_name = $surname.", ".$name;
			} elsif ( $surname and !$name  ) {
				$personal_name = $surname;
			} elsif ( !$surname and $name  ) {
				$personal_name = $name;
			} else {
				#Warning: It supposed this never happend...
				$personal_name = ' ';
			}
			my $newField = MARC::Field->new('700','1','','a' => $personal_name);	# This "700" should change after with what it should
			if ( $function ) { $newField->add_subfields( 'e' => $function ) }
			if ( $date ) { $newField->add_subfields( 'd' => $date ) }
			push(@newPersonalNames, $newField);
		}
	}
	INPUT_FIELD_029: {	# CORPORATE_NAME
		my @inputCorporateNames = $iRec->field( $iCorporateNameTag );
		foreach my $corporateName ( @inputCorporateNames ) {
			#~ Si NO está ^j: Está el ^e o el ^n y no el otro, lo migro al $a. Si están los dos, me quedo con ^n.
			#~ Si está ^j, éste se migra al $a y los ^e o ^n(usando la política de antes), se migran al $b.
			my $corporate_name_entry = "";
			my $subordinate_unit = "";

			#~ $a - Corporate name or jurisdiction name as entry element (NR)
			#~ $b - Subordinate unit (R) 
			#~ $c - Location of meeting (NR) 
			my $newField = MARC::Field->new('710','2','','a' => $corporate_name_entry);	# This "710" should change after with what it should

			if ( ! defined $corporateName->subfield('j') ) {
				if ( defined $corporateName->subfield('n') ) {
					#~ $corporate_name = $corporateName->subfield('n') );
					$newField->update( 'a' => $corporateName->subfield('n') );
				} elsif ( defined $corporateName->subfield('e') ) {
					$newField->update( 'a' => $corporateName->subfield('e') );
				} else {
					#~ WARNING: This should not be happening... No name nor editor!
					;
				}
			} else {	# We have subfield 'j'
				#~ $corporate_name = $corporateName->subfield('j') );
				$newField->update( 'a' => $corporateName->subfield('j') );
				if ( defined $corporateName->subfield('n') ) {
					#~ $subordinate_unit = $corporateName->subfield('n') );
					$newField->add_subfields( 'b' => $corporateName->subfield('n') );
				} elsif ( defined $corporateName->subfield('e') ) {
					#~ $subordinate_unit = $corporateName->subfield('e') );
					$newField->add_subfields( 'b' => $corporateName->subfield('e') );
				} else {
					#~ WARNING: This should not be happening...
					;
				}
			}

			if ( $corporateName->subfield('f') ) { $newField->add_subfields( 'e' => $corporateName->subfield('f') ) }	# Function
			if ( $corporateName->subfield('s') ) { $newField->add_subfields( 'g' => $corporateName->subfield('s') ) }	# Siglas

			my $location = $corporateName->subfield('l');
			my $country = $corporateName->subfield('p');
			if ( $location ) { $location =~ s/;//g; }	# Removes commas, if any...
			if ( $country ) { $country =~ s/;//g; }
			my $locationOfMeeting = "";
			
			if ( $location and $country ) {
				#~ $locationOfMeeting = $location."; ".$country;
				$newField->add_subfields( 'c' => $location."; ".$country );
			} elsif ( $location and !$country  ) {
				#~ $locationOfMeeting = $location;
				$newField->add_subfields( 'c' => $location );
			} elsif ( !$location and $country  ) {
				#~ $locationOfMeeting = $country;
				$newField->add_subfields( 'c' => $country );
			} else {
				#Warning: It supposed this never happend...
				;
			}
			
			#~ print $newField->as_formatted()."\n";
			push(@newCorporateNames, $newField);
		}
	}

	if ( ( cantNombresPersonalesSinFunc($iRec) + cantNombresCorporativosSinFunc($iRec) ) <= 3 ) {	# Se carga entrada principal: algunos al 1xx, otros al 7xx
		if ( defined( $iRec->field($iPersonalNameTag) ) and !defined($iRec->subfield($iPersonalNameTag,$iFunctionSubfieldCode))) {		#~ if (  existe(28[1])  AND  NOT( existe(28[1]^f) ) ) {	# Hay entrada principal de Autor Personal
			# El 110 queda libre
			#~ 28[1] al 100[1]	# Si no existe ^a OR ^b: Warning
			#~ 28[2] al 700[1]
			#~ 28[3] al 700[2]
			#~ 28[+3] al 700[+2]
			#~ 29: Todo al 710 (ver aclaraciones; une e y n...)
			my $occ = 1;
			foreach my $personalName ( @newPersonalNames ) {
				if ( $occ == 1 ) {
					updateFieldTag($personalName, '100');
				} else {
					updateFieldTag($personalName, '700');
				}
				$occ++;
			}
			foreach my $corporateName ( @newCorporateNames ) {
				updateFieldTag($corporateName, '710');
			}
		} elsif ( defined( $iRec->field($iCorporateNameTag) ) and !defined($iRec->subfield($iCorporateNameTag,$iFunctionSubfieldCode))) {
			# El 100 queda libre
			#~ 29[1] al 110[1]
			#~ 29[2] al 710[1]
			#~ 29[3] al 710[2]
			#~ 29[+3] al 710[+2]
			#~ Todo el 28 al 700
			my $occ = 1;
			foreach my $corporateName ( @newCorporateNames ) {
				if ( $occ == 1 ) {
					updateFieldTag($corporateName, '110');
				} else {
					updateFieldTag($corporateName, '710');
				}
				$occ++;
			}
			foreach my $personalName ( @newPersonalNames ) {
				updateFieldTag($personalName, '700');
			}
		} else {
			#~ todo 28 al 700
			#~ todo 29 al 710
			foreach my $personalName ( @newPersonalNames ) {
				updateFieldTag($personalName, '700');
			}
			foreach my $corporateName ( @newCorporateNames ) {
				updateFieldTag($corporateName, '710');
			}
		}
	} else {	# Se carga todo en 7xx; El 100 y 110 quedan libres
		#~ todo 28 al 700
		#~ todo 29 al 710
		foreach my $personalName ( @newPersonalNames ) {
			updateFieldTag($personalName, '700');
		}
		foreach my $corporateName ( @newCorporateNames ) {
			updateFieldTag($corporateName, '710');
		}
}

	$oRec->insert_fields_ordered( @newPersonalNames );
	$oRec->insert_fields_ordered( @newCorporateNames );
	# ToDo-Closed(No se migran): ¿NOMBRE, LUGAR y RESPONSABLE de REUNIÓN...? 40, 43, al 111, 711

	return $oRec;
}

sub translateSeries {
	my ($iRec, $oRec) = @_;
	my $titulo_de_serie_tag = '036';
	my $responsable_de_serie_tag = '039';
	
	my @fields = $iRec->field( $titulo_de_serie_tag );
	foreach my $field ( @fields ) {
		my @outputSubfields = ();

		my $titulo_de_serie = $field->subfield('t');
		my $responsable_de_serie = $iRec->subfield($responsable_de_serie_tag, 'a');	# @Hipotesis: Lo supongo NR aunque es R
		my $seriesStatement = "";

		if ( $titulo_de_serie and $responsable_de_serie ) {
			push(@outputSubfields, 'a', $titulo_de_serie." / ".$responsable_de_serie );
		} elsif ( $titulo_de_serie and !$responsable_de_serie  ) {
			push(@outputSubfields, 'a', $titulo_de_serie );
		} elsif ( !$titulo_de_serie and $responsable_de_serie  ) {
			push(@outputSubfields, 'a', $responsable_de_serie );
		} else {
			#Warning: This should never happend...
			;
		}

		if ( $iRec->subfield( $titulo_de_serie_tag, 's') ) {
			push(@outputSubfields, 'a', $iRec->subfield( $titulo_de_serie_tag, 's') );
		}
		if ( $iRec->subfield( $titulo_de_serie_tag, 'u') ) {
			push(@outputSubfields, 'a', $iRec->subfield( $titulo_de_serie_tag, 'u') );
		}

		my $nroSerieMonog = $iRec->subfield('012','a');	# @Hipotesis: Lo supongo NR aunque es R
		if ( $nroSerieMonog ) {
			push(@outputSubfields, 'v', $nroSerieMonog );
		}

		if ( @outputSubfields ) {
			my $newField = MARC::Field->new('490', '0', '', @outputSubfields);
			$oRec->insert_fields_ordered( $newField );
		}
	}

	return $oRec;
}

sub translateEdition {
	my ($iRec, $oRec) = @_;
	my $field250a = "";
	my @outputSubfields = ();

	#~ 250$a - Edition statement (NR)
	#~ 250$b - Remainder of edition statement (NR) 
	my $iEdition = $iRec->subfield('044','a');
	if ( $iEdition ) {
		$iEdition =~ s/ed\./ed/g;
		$iEdition =~ s/ +ed +/ ed /g;
		my @edition = split(/ed/, $iEdition);
		my ($field250a,$field250b) = @edition;
		if ( $field250a ) {
			$field250a =~ s/^\s+//;
			$field250a =~ s/\s+$//;
			$field250a .= " ed.";
		}
		if ( $field250b ) {
			$field250b =~ s/^\s+//;
			$field250b =~ s/\s+$//;
		}


		if ( $field250a ) {
			push(@outputSubfields, 'a', $field250a );
		}
		if ( $field250b ) {
			push(@outputSubfields, 'b', $field250b );
		}

		if ( @outputSubfields ) {
			my $newField = MARC::Field->new('250', '', '', @outputSubfields);
			$oRec->insert_fields_ordered( $newField );
		}
		
	}
	return $oRec;
}

sub cleanDate {	# Sanitize years from date
	my $date = shift;
	if ( ($date =~ m/\?/) || ($date =~ m/-[^0-9c]/i) ) {	#~ If - or ?, remove brackets, add lead&end brackets
		$date =~ s/\[//g;
		$date =~ s/\]//g;
		$date =~ s/^(.*)$/\[$1\]/g;
	}
	return $date;
}

sub translatePublication {
	my ($iRec, $oRec) = @_;
	
	#~ Publication Distribution
	my @publicationDistributionSubfields = ();

	my $iLocation = $iRec->subfield('047','l');
	if ( $iLocation ) {
		$iLocation = $iLocation." : ";
		push(@publicationDistributionSubfields, 'a', $iLocation);
	}

	my $iEditor = $iRec->subfield('047','e');
	if ( $iEditor ) {
		$iEditor = $iEditor.", ";
		push(@publicationDistributionSubfields, 'b', $iEditor);
	} 

	my $iPublication = $iRec->subfield('045','a');
	if ( $iPublication ) {
		$iPublication = cleanDate($iPublication);
		push(@publicationDistributionSubfields, 'c', $iPublication);
	} 

	if ( @publicationDistributionSubfields ) {
		my $newField = MARC::Field->new('260', '', '', @publicationDistributionSubfields);
		$oRec->insert_fields_ordered( $newField );
	}
	
	#~ Country Publishing
	my @countryPublishingSubfields = ();
	my @fields = $iRec->field( '048' );
	#~ my $occ = 1;
	foreach my $field ( @fields ) {
		my $iCountryPublishing = $field->subfield('a');
		if ( $iCountryPublishing ) {
			my $MARCCountryPublishing = iso3166_to_marc( $iCountryPublishing );
			$MARCCountryPublishing =~ s/ //g;	# Strip spaces
			push(@countryPublishingSubfields, 'a', $MARCCountryPublishing );	# Eg.: "sp " or "xxk"
			push(@countryPublishingSubfields, 'c', lc( $iCountryPublishing ) );	# Eg.: "ES " or "GB"
		}
		#~ $occ++;
	}
	# Translate from field OCC to SUBfieldOCC, thus, this if is out of foreach
	if ( @countryPublishingSubfields ) {
		my $newField = MARC::Field->new('044', '', '', @countryPublishingSubfields);
		$oRec->insert_fields_ordered( $newField );
		#~ print "ANTES: ".$iRec->subfield('045','a')."\t"."DESPUES: ".$oRec->subfield('260','a')."\n";
	}
	
	return $oRec;
}

sub isOrIncludesATranslation {
	#~ 041 - Language Code (R), First Indicator, Translation indication
	#~ 0 - Item not a translation/does not include a translation
	#~ 1 - Item is or includes a translation	
	my ($iRec) = @_;
	my $field_059a =  $iRec->subfield( '059', 'a' );
	my $field_028f =  $iRec->subfield( '028', 'f' );

	if ( defined( $field_059a ) and ($field_059a =~ m/(original|traducción)/i) ) {
		#~ if ( $field_059a =~ m/(original|traducción)/i ) {
		return 1;
	} elsif ( defined( $field_028f ) and ($field_028f =~ m/(^tr)/i) ) {
		return 1;
	} else {
		return 0;
	}
}

sub translateLanguage {	#50a to 41a aprox
	my ($iRec, $oRec) = @_;
	
	my $lang_code_alpha2 = "||";
	my $lang_code_alpha3 = "|||";
	
	my @fields = $iRec->field( '050' );
	
	my $occ = 1;
	foreach my $field ( @fields ) { # foreach input lang...
		my @languagesSubfields = ();
		$lang_code_alpha2 = $field->subfield('a');
		if ( $lang_code_alpha2 ) {
			if ( is_valid_language( $lang_code_alpha2 ) ) {
				$lang_code_alpha3 = language_code2code( $lang_code_alpha2 , LOCALE_LANG_ALPHA_2, LOCALE_LANG_ALPHA_3 );	# Get lang code and convert from two to three type
			} else {
				$lang_code_alpha3 = "|||";
			}
			if ( ($occ > 1) or (isOrIncludesATranslation($iRec)) ) {	# First one is on 008/35-37, here the other ones (if any)
				push(@languagesSubfields, 'a', $lang_code_alpha3 );
			} else {
				#~ ToDo-Done(Done on 008 section): Set here $ 	 to 008/35-37, or set it at the end with a function...
				;
			}
		}
		$occ++;
		
		if ( @languagesSubfields ) {
			my $newField = MARC::Field->new('041', isOrIncludesATranslation($iRec) , '', @languagesSubfields);
			$oRec->insert_fields_ordered( $newField );
		}
	}
	return $oRec;
}

sub translatePhysicalDescription {	#52 to 300 aprox
	my ($iRec, $oRec) = @_;
	my @physicalDescriptionSubfields = ();
	my $field_052e =  $iRec->subfield( '052', 'e' );
	my $extent = $field_052e;	# 52e is exactly extent, $a - Extent: Number of physical pages, volumes...
	my $field_052i =  $iRec->subfield( '052', 'i' );

	if ( $extent ) {	# To set $a in first place
		push(@physicalDescriptionSubfields, 'a', $extent );
	}

	if ( $field_052i ) {
		if ( $field_052i =~ m/^[0-9].*$/i ) {
			push(@physicalDescriptionSubfields, 'c', $field_052i );
		} else {
			#~ my ($field_052i_to_300b, $field_052i_to_300c, $field_052i_to_300e) = $field_052i =~ /^(.+);(.+)\+(.+)/igs;
			my $match;

			($match) = $field_052i =~ m/^(.*?)(?=;|$)/igs;	# From begining to ";", else end
			if ( $match ) {
				$match =~ s/^\s+|\s+$//g ;	# Trim
				push(@physicalDescriptionSubfields, 'b', $match." ; " );
				$extent = $extent." : ";
			} else {
				$extent = $extent." ; ";
			}
			#~ si existe($b) {
				#~ al final de $a " : "
				#~ al final de $b " ; "
			#~ } else {
				#~ al final de $a " ; "
			#~ }

			($match) = $field_052i =~ m/(?<=;)(.*?)(?=\+|$)/igs;	# From ";" to "+", else end
			if ( $match ) {
				$match =~ s/^\s+|\s+$//g ;	# Trim
				$match =~ s/cm\./cm/g ;	# Removes dot after measure unit
				push(@physicalDescriptionSubfields, 'c', $match );
			}

			($match) = $field_052i =~ m/\+(.+)$/igs;	# From "+" until the end
			if ( $match ) {
				$match =~ s/^\s+|\s+$//g ;	# Trim
				push(@physicalDescriptionSubfields, 'e', $match );
			}
		}
	}
	
	if ( @physicalDescriptionSubfields ) {
		my $newField = MARC::Field->new('300', '', '', @physicalDescriptionSubfields);
		if ( $extent ) {	# To set $a in first place
			$newField->update( a => $extent );
		}
		$oRec->insert_fields_ordered( $newField );
	}
	
	return $oRec;
}

sub translateNotes {
	my ($iRec, $oRec) = @_;

	# THESIS NOTES
	my @fields_055 = $iRec->field( '055' );
	foreach my $field ( @fields_055 ) {
		my @thesisNotesSubfields = ();
		my $field_055n = $field->subfield('n');
		my $field_055e = $field->subfield('e');
		my $field_055s = $field->subfield('s');
		my $field_055d = $field->subfield('d');
		my $thesisNote = "";
		# ^n -- ^e. ^s, ^d
		if ( $field_055n ) {
			$thesisNote .= $field_055n;
		}
		if ( $field_055e ) {
			$field_055e =~ s/--//g;
			$thesisNote .= " -- ".$field_055e;
		}
		if ( $field_055s ) {
			$field_055s =~ s/\.//g;
			$thesisNote .= ". ".$field_055s;
		}
		if ( $field_055d ) {
			$field_055d =~ s/,//g;
			$thesisNote .= ", ".$field_055d;
		}
		if ( $thesisNote ) {
			push(@thesisNotesSubfields, 'a', $thesisNote );
		}
		if ( @thesisNotesSubfields ) {
			my $newField = MARC::Field->new('502', '', '', @thesisNotesSubfields);
			$oRec->insert_fields_ordered( $newField );
		}

		# Some other thesis notes out of MARC 21
		my @thesisNotesSubfields_2 = ();
		my $field_055c = $field->subfield('c');
		my $field_055g = $field->subfield('g');
		if ( $field_055c ) {
			push(@thesisNotesSubfields_2, 'c', $field_055c );
		}
		if ( $field_055g ) {
			push(@thesisNotesSubfields_2, 'g', $field_055g );
		}

		if ( @thesisNotesSubfields_2 ) {
			my $newField = MARC::Field->new('955', '', '', @thesisNotesSubfields_2);
			$oRec->insert_fields_ordered( $newField );
		}
	}
	#~ $oRec = moveSubfields($iRec, $oRec, '055', 'c', '502', 'c');	# This aren't notes but... ehem...
	#~ $oRec = moveSubfields($iRec, $oRec, '055', 'g', '502', 'g');

	my @fields_059 = $iRec->field( '059' );
	foreach my $field ( @fields_059 ) {
		my $field_059 = $field->subfield('a');
		if ( $field_059 ) {
			if ( $field_059 =~ m/(bibliografía|bibliografia|índice|indice)/i ) {
				$field_059 =~ s/Adjunta//gi;
				$field_059 =~ s/Anexa//gi;
				$oRec->insert_fields_ordered( MARC::Field->new('504', '', '', 'a' => $field_059) );
			} elsif ( $field_059 =~ m/La biblioteca posee/i ) {
				$oRec->insert_fields_ordered( MARC::Field->new('505', '1', '', 'a' => $field_059) );
			} elsif ( $field_059 =~ m/(Atlas|suplemento)/i ) {
				$oRec->insert_fields_ordered( MARC::Field->new('525', '', '', 'a' => $field_059) );
			} else {
				$oRec->insert_fields_ordered( MARC::Field->new('500', '', '', 'a' => $field_059) );
			}
			#~ $oRec->insert_fields_ordered( $newField );
		}
	}
	return $oRec;
}

sub getCSVRow {	# Return first row where needle is found on given cvs
	my ($needle, $whereField, $filename) = @_;
	my $csv = Text::CSV_XS->new ({
		binary => 1,
		auto_diag => 1,
		sep_char => ',' # not really needed as this is the default
	});
	open ( my $data, "<:encoding(utf8)", $filename ) or die "$filename: $!";
	#~ local $/; # enable localized slurp mode
	#~ my $data = <$fh>;
	my $row = undef;
	#~ my $header_row = $csv->getline( $data );
	while ( $row = $csv->getline( $data ) ) {
	 #~ my $aaa = 0;
		if ( defined( $row->[$whereField] ) && ( $row->[$whereField] =~ m/^\s*\Q$needle\E\s*$/i ) ) {	# whereField field should match, $column_idx is zero-based
			 #~ print Dumper ($needle, $whereField, $filename, $row);
			 #~ $aaa = 1;
			 #~ if ( defined ($aaa) && ($aaa == 1) ) { print Dumper ($needle, $whereField, $filename, $row); }
			last;
		} else {
			next;
			#~ push @rows, $row;
		}
	}
	$csv->eof or $csv->error_diag();	#	if (not $csv->eof) { $csv->error_diag(); }
	#~ close $fh;	# ex "$data"
	close $data;
	#~ if ( defined ($aaa) && ($aaa == 1) ) { print Dumper ($needle, $whereField, $filename, $row); }
	return $row;
	#~ return @rows;

}

sub translateSubject {
	my ($iRec, $oRec) = @_;
	
	my @fields = $iRec->field( '065' );

	foreach my $field ( @fields ) {	#~ foreach $termino {    # Por cada término/OCC del v65
		my @subjectSubfields = ();
		if ( my $subject = $field->subfield('a') ) {
			my $whereField;	# A=0, B=1, C=2, D=3, E=4 ,F=5 ,G=6 ,H=7
			my $row = undef;

			 #~ $row = getCSVRow($subject, $whereField = 7, $subject_CSV_file);
			 #~ print Dumper($row);

			if ( $row = getCSVRow($subject, $whereField = 7, $subject_CSV_file) ) {    # Si coincide EXACTAMENTE $término con ALGUNA fila de ColH
				#~ 651$a = $termino    # GEOGRAFICO
				push(@subjectSubfields, 'a', $subject );
				if ( @subjectSubfields ) {
					my $newField = MARC::Field->new('651', '', '4', @subjectSubfields);	# Ind2=4 : Source not specified
					$oRec->insert_fields_ordered( $newField );
				}
			} elsif ( $row = getCSVRow($subject, $whereField = 0, $subject_CSV_file) ) {    # Si coincide EXACTAMENTE $término con ALGUNA fila de ColA
				if ( $row->[1] =~ m/^\s*\?\s*$/i or $row->[1] =~ m/^\s*REVISAR\s*$/i ){    # Para la fila de ColA, busco coincidencia exacta
					#~ 653$a = $termino    # Es palabra clave
					push(@subjectSubfields, 'a', $subject );
					if ( @subjectSubfields ) {
						my $newField = MARC::Field->new('653', '', '4', @subjectSubfields);	# Ind2=4 == Source not specified
						$oRec->insert_fields_ordered( $newField );
					}
				} elsif ( $row->[1] =~ m/^\s*REEMPLAZAR\s*$/i ) {    # Ruego a Dios que ColC y ColD tengan el contenido que corresponde...
					#~ 650$a = ColC    # termino descriptor
					#~ 650$2 = ColD    # fuente descriptor
					push(@subjectSubfields, 'a', $row->[2] );
					push(@subjectSubfields, '2', $row->[3] );
					if ( @subjectSubfields ) {
						my $newField = MARC::Field->new('650', '', '7', @subjectSubfields);	# Ind2=4 == Source not specified
						$oRec->insert_fields_ordered( $newField );
					}
				} else {
					#~ 650$a = ColA    # termino descriptor
					#~ 650$2 = ColB    # fuente descriptor    # Ruego a Dios que acá esté la fuente...
					push(@subjectSubfields, 'a', $subject );
					push(@subjectSubfields, '2', $row->[1] );
					if ( @subjectSubfields ) {
						my $newField = MARC::Field->new('650', '', '7', @subjectSubfields);	# Ind2=4 == Source not specified
						$oRec->insert_fields_ordered( $newField );
					}
				}
			} else {
				#~ 653$a = $termino    # Es palabra clave
				push(@subjectSubfields, 'a', $subject );
				if ( @subjectSubfields ) {
					my $newField = MARC::Field->new('653', '', '4', @subjectSubfields);	# Ind2=4 == Source not specified
					$oRec->insert_fields_ordered( $newField );
				}
			}
		}
		#~ if ( $subject ) {
			#~ push(@subjectSubfields, 'a', $subject );
		#~ }

		#~ if ( @subjectSubfields ) {
			#~ my $newField = MARC::Field->new('650', '', '7', @subjectSubfields);
			#~ $oRec->insert_fields_ordered( $newField );
		#~ }
	}
	
	return $oRec;
#~ TESAURO DESCRIPTORES, Tesauro-fiuba(2).xlsx, ver google doc
#~ foreach $termino {    # Por cada término/OCC del v65
    #~ if ( $termino estáEn ColH ) {    # Si coincide EXACTAMENTE $término con ALGUNA fila de ColH
        #~ 651$a = $termino    # geografico
    #~ } elsif ( $termino estáEn ColA ) {    # Si coincide EXACTAMENTE $término con ALGUNA fila de ColA
        #~ if ( ColB=="?" OR ColB=="REVISAR" ){    # Para la fila de ColA, busco coincidencia exacta
            #~ 653$a = $termino    # Es palabra clave
        #~ } elseif ( ColB=="REEMPLAZAR" ) {    # Ruego a Dios que ColC y ColD tengan el contenido que corresponde...
            #~ 650$a = ColC    # termino descriptor
            #~ 650$2 = ColD    # fuente descriptor
        #~ } else {
            #~ 650$a = ColA    # termino descriptor
            #~ 650$2 = ColB    # fuente descriptor    # Ruego a Dios que acá esté la fuente...
        #~ }
    #~ } else {
        #~ 653$a = $termino    # Es palabra clave
    #~ }
#~ }


}

sub translateClassificationNumber {
	my ($iRec, $oRec) = @_;
	my @subfields = ();

	#~ my $iField_075l = $iRec->subfield( '075', 'l' );	# Is NR in input format (BIBUN)

	my $iField_075c = $iRec->subfield( '075', 'c' );	# Is NR in input format (BIBUN)
	my $UDC_Number;
	my $commonAuxiliarySubdivision;

	if ( $iField_075c ) {

		if ( not defined( $iRec->field('055') ) ) {	# If Not thesis
			if ( $iField_075c =~ m/^([^\(]+).*$/ ) {	# sign1 (subdiv) => sign1
				$UDC_Number = $1;
				push(@subfields, 'a', $UDC_Number );
			}
			if ( $iField_075c =~ m/(\(.*\))/ ) {	# Just subdiv
				$commonAuxiliarySubdivision = $1;
				push(@subfields, 'x', $commonAuxiliarySubdivision );
			}
		} else {	# ES TESIS O TRABAJO PROFESIONAL
			$oRec = moveSubfields_NR($iRec, $oRec, '075', 'c', '084', 'a');
		}
		#~ if ( $commonAuxiliarySubdivision ) { print "A: ".$iField_075c."\t 80a: ".$UDC_Number."\t 80x: ".$commonAuxiliarySubdivision."\n"; }
	}

	if ( @subfields ) {
		my $newField = MARC::Field->new('080', '0', '', @subfields);
		$oRec->insert_fields_ordered( $newField );
	}

	# Librística, call number
	#~ Thesis dont have input v75^l
	$oRec = moveSubfields_NR($iRec, $oRec, '075', 'l', '084', 'a');

	return $oRec;
}

sub translateDataSourceEntry {
	my ($iRec, $oRec) = @_;
	my @subfields = ();

	my $iField_076a = $iRec->subfield( '076', 'a' );	# Is NR in input format (BIBUN)

	if ( $iField_076a ) {
		push(@subfields, 'o', $iField_076a );
	}
	if ( @subfields ) {
		my $newField = MARC::Field->new('786', '1', '', @subfields);
		$oRec->insert_fields_ordered( $newField );
	}

	return $oRec;
}

sub translateAvailability {
	my ($iRec, $oRec) = @_;
	my @subfields = ();

	my $iField_085a = $iRec->subfield( '085', 'a' );	# Is NR in input format (BIBUN)
	my $iField_085v = $iRec->subfield( '085', 'v' );	# Is NR in input format (BIBUN)
	my $iField_085c = $iRec->subfield( '085', 'c' );	# Is NR in input format (BIBUN)

	if ( $iField_085a ) {
		push(@subfields, 'a', $iField_085a );
	}
	if ( $iField_085v ) {
		push(@subfields, 'v', $iField_085v );
	}
	if ( $iField_085c ) {
		push(@subfields, 'c', $iField_085c );
	}
	if ( $iRec->subfield( '085', '9' ) ) {
		push(@subfields, '9', $iRec->subfield( '085', '9' ) );
	}

	if ( @subfields ) {
		my $newField = MARC::Field->new('985', '', '', @subfields);
		$oRec->insert_fields_ordered( $newField );
	}

	return $oRec;
}

sub translateArchiveCharacteristics {
	my ($iRec, $oRec) = @_;
	my @subfields = ();

	my $iField_020a = $iRec->subfield( '120', 'a' );	# Is NR in input format (BIBUN)
	my $iField_020b = $iRec->subfield( '120', 'b' );	# Is NR in input format (BIBUN)
	my $iField_020d = $iRec->subfield( '120', 'd' );	# Is NR in input format (BIBUN)

	if ( $iField_020a ) {
		push(@subfields, 'a', $iField_020a );
	}
	if ( $iField_020b ) {
		push(@subfields, 'b', $iField_020b );
	}
	if ( $iField_020d ) {
		push(@subfields, 'c', $iField_020d );
	}

	if ( @subfields ) {
		my $newField = MARC::Field->new('920', '', '', @subfields);
		$oRec->insert_fields_ordered( $newField );
	}
	return $oRec;
}

sub translateBiblioLocal {
	my ($iRec, $oRec) = @_;
	my @subfields = ();

	if ( defined($iRec->field('055')) ) {	# Is thesis
		push(@subfields, 'f', 'TES' );
	} else {
		push(@subfields, 'f', 'BKS' );
	}

	push(@subfields, 'n', '0' );

	if ( @subfields ) {
		my $newField = MARC::Field->new('942', '', '', @subfields);
		$oRec->insert_fields_ordered( $newField );
	}
	
	return $oRec;
}

sub translateHoldingsData {	# 952
	#~ See: http://wiki.koha-community.org/wiki/Holdings_data_fields_%289xx%29
	#~ The fields in bold are mandatory for the standard Koha setup: $a $b $o $p $y
	my ($iRec, $oRec) = @_;

	my @fields_998 = $iRec->field( '998' );
	foreach my $field ( @fields_998 ) {
		my @holdingSubfields = ();
		push(@holdingSubfields, '0', "0" );
		push(@holdingSubfields, '1', "0" );
		push(@holdingSubfields, '4', "0" );
		push(@holdingSubfields, '5', "0" );
		push(@holdingSubfields, '6', "0" );
		push(@holdingSubfields, 'a', "BC" );
		push(@holdingSubfields, 'b', "BC" );
		

		#~ 952$d
		my $itemsDateaccessioned = $iRec->subfield('913','a');	# So the format is: YYYY-MM-DD (Ref; http://wiki.koha-community.org/wiki/Holdings_data_fields_%289xx%29#Holdings_data_-_How_to_insert_dates )
		if ( $itemsDateaccessioned ) {
			$itemsDateaccessioned =~ s/\s+/-/g;
			if ( $itemsDateaccessioned =~ m/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/i ) {
				push(@holdingSubfields, 'd', $itemsDateaccessioned );
			}
		}
		
		my $itemsPrice = $iRec->subfield('095','a');
		if ( $itemsPrice ) { push(@holdingSubfields, 'g', $itemsPrice ); }

		# ToDo: Difference between Item Location and Item Call Number..?
		my $classNumber = $iRec->subfield('075','c');
		my $bookNumber = $iRec->subfield('075','l');
		my $itemCallnumber = "";
		if ( $classNumber ) { $itemCallnumber .= $classNumber; }
		if ( $bookNumber ) { $itemCallnumber .= ", ".$bookNumber; }
		if ( $itemCallnumber ) { push(@holdingSubfields, 'o', $itemCallnumber ); }	# If string not empty. Koha full call number: items.itemcallnumber
		
		my $barcode = $field->subfield('a');
		my $itemsItype = "";
		my $lastchar = "";

		my $whereField;	# A=0, B=1, C=2, D=3, E=4 ,F=5 ,G=6 ,H=7
		my $row = undef;
		my $notForLoan = undef;

		if ( $barcode ) {
			$barcode =~ s/ //g;	# Strip spaces
			$barcode = uc($barcode);	# UPPERCASE
			$lastchar = substr($barcode,-1);
			if ( $lastchar eq "X" ) {
				$itemsItype = "PR";
			} elsif ( $lastchar eq "*" ) {
				$itemsItype = "EE";
			} elsif ( $lastchar eq "+" ) {
				$itemsItype = "SALA";
			} elsif ( $iRec->field('055') ) {	# If it is a Thesis...
				$itemsItype = "TE";
			} elsif ( $iRec->subfield('085','a') and ($iRec->subfield('085','a') =~ m/^REF$/i) ) {	# REFerence
				$itemsItype = "REF";
			} elsif ( $row = getCSVRow($barcode, $whereField = 3, $bookbinding_CSV_file) ) {	# Está en el taller
				my $barcode_inCSV = $row->[6];
				$barcode_inCSV =~ s/ //g;	# Strip spaces
				if ( $barcode_inCSV =~ m/(^EE$|^DEP$|^PR$|^SALA$)/i ) {
					$itemsItype = $row->[6];
				} else {	# Item is in limbo... "descatalogado"
					$itemsItype = "LI";
					push(@holdingSubfields, 'c', 'PROC' );
				}
				$notForLoan = 1;
				push(@holdingSubfields, 'f', $row->[7] );	# Fecha Envío Taller (ver [1])
			} else {
				$itemsItype = "LI";	# Item is in limbo...
			}

			$barcode =~ s/X$//g;
			$barcode =~ s/\*$//g;
			$barcode =~ s/\+$//g;
			
			push(@holdingSubfields, 'p', $barcode );
			if ( $itemsItype ) { push(@holdingSubfields, 'y', $itemsItype ); }
		}

		#~ 952$7
		if ( defined($notForLoan) ) {
			push(@holdingSubfields, '7', '1' );	# NOT FOR LOAN, in book binding.
		} elsif ( not $iRec->subfield('065','a') ) {
			# NOT FOR LOAN, WITHOUT HEADINGS (sin descriptores)
			push(@holdingSubfields, 'c', 'PROC' );
			push(@holdingSubfields, '7', '4' );
		} else {
			push(@holdingSubfields, '7', "0" );
		}

		my $price = $iRec->subfield('095','a');
		if ( $price ) {
			$price =~ s/\{dollar\}/ARS /gi;	# extract first three chars... shouldn't be necessary
			push(@holdingSubfields, 'g', $price );
		}
		
		if ( @holdingSubfields ) {
			my $newField = MARC::Field->new('952', '', '', @holdingSubfields);	# ind2==8!?
			$oRec->insert_fields_ordered( $newField );
		}
	}

	return $oRec;
}

sub translateErrors {
	my ($iRec, $oRec) = @_;	# ToDo: Need also parameters to move...
	#~ ToDo: for any field, if exist, move it somehow to oRec... subfields $9
	return $oRec;
}

sub translateBIBUN2MARC {
	my ($irec) = @_;
	
	my $orec = MARC::Record->new();

	 #~ print "Antes\t".$irec->leader()."\n";
	 #~ my $inputLDR = $irec->leader();
	 #~ print "Medio\t".changeLeader($inputLDR, 18, 'x')."\n";
	 #~ $orec->leader( changeLeader($inputLDR, 18, 'x') );
	 #~ print "Después\t".$orec->leader()."\n";
	 #~ exit 1;


	#~ LEADER	For eg: Len=03366, Sta=n, Typ=a, Lev=m, Ctrl=, Chr=, Enc=I, Cat=a, Rel=.
	my $iLeader = $irec->leader();
	$orec->leader( changeLeader($iLeader, 5, 'c') );	#~ 05 - Record status = 'c'

	if ( defined( $irec->field('055') ) ) {
		$orec->leader( changeLeader($orec->leader(), 6, 't') );	#~ 06 - Type of record = 't' FOR THESIS; t - Manuscript language material
	} else {
		$orec->leader( changeLeader($orec->leader(), 6, 'a') );	#~ 06 - Type of record = 'a' ('z' for authority)
	}

	$orec->leader( changeLeader($orec->leader(), 7, 'm') );	#~ 07 - Bibliographic level = 'm'	m - Monograph/Item
	#~ $orec->leader( changeLeader($orec->leader(), 8, 'c') );	#~  08 - Type of control = ""
	$orec->encoding('UTF-8');	#~  09 - Character coding scheme = 'a'
	#~ $orec->leader( changeLeader($orec->leader(), 10, '2') );	#~  10 - Indicator count = ""
	#~ $orec->leader( changeLeader($orec->leader(), 11, '2') );	#~  11 - Subfield code count = ""
	$orec->leader( changeLeader($orec->leader(), 17, ' ') );	#~  17 - Encoding level = ""
	$orec->leader( changeLeader($orec->leader(), 18, 'a') );	#~  18 - Descriptive cataloging form = ""
	$orec->leader( changeLeader($orec->leader(), 19, ' ') );	#~  19 - Multipart resource record level = ""
	#~ $orec->leader( changeLeader($orec->leader(), 23, 'c') );	#~  23 - Undefined = ""
	#~  LEADER SIZE: ToDo: Last step (if needed)! // Función *interna*, ¿importa, no lo hace solo?
	#~  Ver https://metacpan.org/module/MARC::Record#set_leader_lengths-reclen-baseaddr-	#~  set_leader_lengths( $reclen, $baseaddr )
		#~ $orec->set_leader_length( length($orec->as_usmarc()), $offset );
		 #~ $orec->set_leader_length( length($orec->as_usmarc()), 0 );	# ToDo: Activate...?

	#001
	# NRO. ACCESO
	if ( $irec->field('911')->subfield('a') ) {
		$orec->insert_grouped_field( MARC::Field->new('001', $irec->field('911')->subfield('a') ) );
	} else {
		#$orec->append_fields( MARC::Field->new('001', $count + BIBLIONUMBER_OFFSET ) );
		#~ ToDo: Log this type of errors...
		 print "ERROR: Record without biblionumber".$irec->as_formatted();
		 exit 1;
	}
	#~ Is useless to put something on tag 999, they are overwritten with Koha asigned biblionumber:
	#~ $orec = moveSubfields($irec, $orec, '911', 'a', '999', 'c');
	#~ $orec = moveSubfields($irec, $orec, '911', 'a', '999', 'd');
	
	#003
	$orec->insert_grouped_field(
		MARC::Field->new('003',$marcorgcode)
	);
	#005
	## figure out the contents of our new 005 field.
	my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
	$year += 1900; $mon += 1; # catering to offsets.
	my $datetime = sprintf("%4d%02d%02d%02d%02d%02d.0",
	$year,$mon,$mday,$hour,$min,$sec);
	## create a new 005 field using our new datetime.
	$orec->insert_grouped_field(
		MARC::Field->new('005',$datetime)
	);

	INPUT_FIELD_008: {	# 008
		my $f008 = "000101s1500    ag_||||| |||| 00| 0 spa d";	# The lenght of this MUST be equal to 40 (00-39)
				   #~ "940308t|||||||||||||||| ||||||||||0spa|21"
				   #~ "008 741021s1884    enkaf         000 1 eng d"
				   #~ "110608s1983 nyu||||| |||| 00| 0 eng d"	# De FF...
				   #~ "920624t|||||||||||||||| |||||||||| spa|d"	# Nuestro
				   #~ "l992 1t|||||||||||||||| ||||||||||0eng|dpa d"	# Nuestro¿

		my $f008_00_05;

		if ( $irec->subfield('913','a') ) {
			$f008_00_05 = $irec->field('913')->subfield('a');
			$f008_00_05 =~ s/[0-9][0-9]([0-9][0-9]) ([0-9][0-9]) ([0-9][0-9])/$1$2$3/g;	# YYYY MM DD to YYMMDD
		} else {
			$f008_00_05 = strftime("%y%m%d", localtime() );
		}

		substr($f008, 0, 6, substr($f008_00_05,0,6) );	#008: 06 - Type of date/Publication status

		my $f008_06;
		if ( $irec->subfield('045','a') ) {	# p(v45)
			my $dates = $irec->field('045')->subfield('a');	# publication date and possibly more
			my @years_from_dates = getYears($dates);
			if ($dates !~ m/c/i) {	#if v45 doesn't contain a "c" or "C"...
				if ( 1 < scalar( @years_from_dates ) ) {	# If more than one year... getYears return array of years on input subfield
					$f008_06 = 'm';
				} else {
					$f008_06 = 's';
				}
			} else {
				$f008_06 = 't';
			}
		
			substr($f008, 6, 1, $f008_06);	#008: 06 - Type of date/Publication status
			
			if (defined $years_from_dates[0]) {
				substr($f008, 7, 4, substr($years_from_dates[0],0,4) );	#008: 07-10 - Date 1
			}

			if (defined $years_from_dates[1] and (scalar( @years_from_dates ) > 1) ) {
				substr($f008, 11, 4, substr($years_from_dates[1],0,4) );	#008: 11-14 - Date 2
			}

		}

		#008: 15-17 - Place of publication, production, or execution
		if ( my $iCountryPublishing = $irec->subfield('048','a') ) {
			my $MARCCountryPublishing = iso3166_to_marc( $iCountryPublishing );
			$MARCCountryPublishing =~ s/^(...).*$/$1/gi;	# extract first three chars... shouldn't be necessary
			substr($f008, 15, 3, $MARCCountryPublishing);
		} elsif ( defined( $irec->subfield('055','s') ) and ($irec->subfield('055','s') =~ m/UBA/i) ) {	# Tesis (thesis) argentina
			substr($f008, 15, 3, "ag ");
		} else {
			substr($f008, 15, 3, "|||");
		}
		

		#~ substr($f008, 18, 17, "||||| |||||||||||");	#008: 18-34 - [See one of the seven separate 008/18-34 configuration sections for these elements.] (008/23:Type of item)
		my $iField_52i = $irec->subfield('052','i');
		if ( defined $iField_52i and ($iField_52i ne '') ) {
			if ( $iField_52i =~ m/il/i ) {
				substr($f008, 18, 1, "a");
			} elsif ( $iField_52i =~ m/mapa/i ) {
				substr($f008, 19, 1, "b");
			} elsif ( $iField_52i =~ m/diagrs/i ) {
				substr($f008, 20, 1, "d");
			} elsif ( $iField_52i =~ m/láms/i ) {
				substr($f008, 21, 1, "f");
			}
		}
		substr($f008, 22, 13, "| |||||||||||");	#008: 22-34 - [See one of the seven separate 008/18-34 configuration sections for these elements.] (008/23:Type of item)
		#18-21 - Illustrations (006/01-04)
		#22 - Target audience (006/05)
		#23 - Form of item (006/06)
		#24-27 - Nature of contents (006/07-10)
		if ( $irec->field('055') ) {	# If it is a Thesis...
			substr($f008, 24, 4, "m|||");
		}
		#28 - Government publication (006/11)
		#29 - Conference publication (006/12)
		#30 - Festschrift (006/13)
		#31 - Index (006/14)
		#32 - Undefined (006/15)
		#33 - Literary form (006/16)
		#34 - Biography (006/17)
		
		#~ 008/35-37, 008: 35-37 - Language
		my $lang_code_alpha2 = "||";
		my $lang_code_alpha3;
		my $lang_min_prob = 0.20;

		if ( my $language = $irec->subfield('050','a') ) {	#if ( $irec->field('050')->subfield('a') ) {
			$lang_code_alpha2 = $language;	# Input language has two chars long
			$lang_code_alpha2 = lc( $lang_code_alpha2 );
			$lang_code_alpha2 =~ s/([a-z][a-z])/$1/;
		} elsif ( my $title = $irec->subfield('024','t') ) {
			if ( my ($language_detected, $probability ) = langof( {method => 'ngrams4' } , $title) ) {
				if ($probability > $lang_min_prob) {
					$lang_code_alpha2 = $language_detected;
				}
			};
		}
		if ( is_valid_language( $lang_code_alpha2 ) ) {
			$lang_code_alpha3 = language_code2code( $lang_code_alpha2 , LOCALE_LANG_ALPHA_2, LOCALE_LANG_ALPHA_3 );	# Get lang code and convert from two to three type
		} else {
			$lang_code_alpha3 = "|||";
		}
		substr($f008, 35, 3, $lang_code_alpha3 );	#008: 35-37 - Language
		substr($f008, 38, 1, "|");	#008: 38 - Modified record
		substr($f008, 39, 1, 'c');	#008: 39 - Cataloging source 

		 if ( length($f008) > 40 ) { print  "ERROR-008: ".$f008."\n"; }
		 #~ print  $f008." - ".$orec->field('001')->as_string()."\n";
		 #~ print  $orec->field('008')->as_string()." - ".$orec->field('001')->as_string()."\n";

		if ( length($f008) <= 40 ) {
			$orec->insert_grouped_field(
				MARC::Field->new('008',$f008)
			);
		} else {
			;	# ToDo: Add warning if 008 is bigger
		}
	}

	# 040 a: Cataloging Source (marcorgcode)
	my $field = MARC::Field->new('040','','','a' => $marcorgcode);
	$orec->insert_grouped_field($field);

	# NIVEL DE REFERENCIA
	$orec = moveSubfields_NR($irec, $orec, '916', 'a', '986', 'a');	# 91x from input == 00x

	# TIPO DE DOCUMENTO
	$orec = moveSubfields($irec, $orec, '917', 'a', '997', 'a');

	# ISBN & ISBN obra com. (multi-volume works, volume set)
	$orec = translateISBN($irec, $orec);

	# TITULO (m)
	$orec = translateTitle($irec, $orec);

	# TITULO (PUBLICACIÓN EN SERIE)
	# RESPONSABLE (PUBLICACIÓN EN SERIE)
	# COD.DOC. NRO DE SERIE MONOGRAFICA
	$orec = translateSeries($irec, $orec);

	# AUTOR
	# AUTOR PERSONAL (m)
	# AUTOR INSTITUCIONAL
	$orec = translateAuthor($irec, $orec);

	# EDICION
	$orec = translateEdition($irec, $orec);

	# FECHA DE PUBLICACIÓN
	# EDITOR Y LUGAR
	# PAIS DE EDICION
	$orec = translatePublication($irec, $orec);

	# IDIOMA DEL DOCUMENTO
	$orec = translateLanguage($irec, $orec);

	# DESCRIPCIÓN FÍSICA
	$orec = translatePhysicalDescription($irec, $orec);

	# PROYECTO PROGRAMA...
	$orec = moveSubfields($irec, $orec, '054', 'i', '954', 'i');
	$orec = moveSubfields($irec, $orec, '054', 'n', '954', 'n');
	$orec = moveSubfields($irec, $orec, '054', 'e', '954', 'e');

	# NOTAS
	$orec = translateNotes($irec, $orec);
	#~ $orec = moveSubfields($irec, $orec, '059', 'a', '504', 'a');
	#~ $orec = moveSubfields($irec, $orec, '055', 'n', '502', 'a'); 	# NOTAS DE TESIS

	# DESCRIPTORES
	# PALABRAS CLAVES
	#~ Subject Added Entry - Topical Term
	if (FULLMIG) {
		$orec = translateSubject($irec, $orec);
	}
	# SINONIMOS
	$orec = moveSubfields($irec, $orec, '063', 'a', '693', 'a');

	# SIGNATURA TOPOGRÁFICA (~75c->~80a)
	$orec = translateClassificationNumber($irec, $orec);

	# BIBLIOTECA DEPOSITARIA
	$orec = translateDataSourceEntry($irec, $orec);
	#~ $orec = moveSubfields($irec, $orec, '076', 'a', '786', 'o');

	# DISPONIBILIDAD
	$orec = translateAvailability($irec, $orec);

	# OTROS DATOS
	$orec = moveSubfields($irec, $orec, '100', 'a', '909', 'a');

	# CARACTERÍSTICAS DEL ARCHIVO
	$orec = translateArchiveCharacteristics($irec, $orec);

	# 942 ENTRADA PARA ELEMENTOS AGREGADOS (KOHA)
	$orec = translateBiblioLocal($irec, $orec);
	#~ $orec->append_fields( MARC::Field->new('942','','','n' => '0' ) );

	# 964 GZIPPED INPUT RECORD: 
	if (ZIPONLOCALFIELD) {
		$orec->append_fields( MARC::Field->new('964','','','a' => marc_2_GZiped_b64( $irec ) ) );
	}

	# 952: HOLDINGS DATA, EJEMPLARES: 
	if (FULLMIG) {
		$orec = translateHoldingsData($irec, $orec);
	}

	# ERRORS: Move $1 to ...
	$orec = translateErrors($irec, $orec);

	return $orec;
}


=head1 AUTHOR
Pablo Bianchi << <pablo.bianchi+bibio@gmail.com> >>

=head1 NAME

migrator.pl

=head1 SYNOPSIS

  migrator.pl
  migrator.pl -v
  
=head1 DESCRIPTION

This script...

=cut

__END__

1;
