package Marcgyver;
no warnings 'uninitialized';	# ToDo: DON'T use this...	
use utf8;
use strict;	# impose a little discipline :P
use warnings;
use Exporter;	# Or  base qw(Exporter);  ?

use MARC::Batch;
#use MARC::Lint;
#use MARC::BBMARC;	Collection of methods and subroutines, add-ons to MARC::Record, MARC::File, MARC::Field.
#use MARC::Errorchecks;	http://search.cpan.org/~eijabb/MARC-Errorchecks-1.13/	http://cpansearch.perl.org/src/EIJABB/MARC-Errorchecks-1.16/lib/MARC/Errorchecks.pm
#use MARC::Record::Stats
use open qw/:std :utf8/;	#sets STDOUT, STDIN & STDERR to use UTF-8....
use MARC::File::XML;	#sudo perl -MCPAN -e 'install MARC::File::XML'
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use MIME::Base64;
use File::Basename;
use Locale::Country;
#use Lingua::Identify qw(:language_identification, langof, set_active_languages);	#sudo perl -MCPAN -e 'install Lingua::Identify'	sudo perl -MCPAN -e 'install Text::Ngram'
	use Lingua::Identify qw(:language_identification langof is_valid_language);
#	set_active_languages( qw(es en fr pt) );

#use Getopt::Long;
#sudo perl -MCPAN -e 'install MARC::Record'
#sudo perl -MCPAN -e 'install MARC::Lint'

our @ISA= qw( Exporter );
our @EXPORT = qw( countMARCRecords record2html print2html print2txt changeLeader moveSubfields moveSubfields_NR getTitleSecondIndicator sortTAGs marc_2_GZiped_b64 GZiped_b64_2_marcXML iso3166_to_marc langof is_valid_language);	# these are exported by default.
#our @EXPORT_OK = qw( export_me export_me_too );	# these CAN be exported.

#~ ToDo:
#~ - Fussion moveSubfields and moveSubfields_NR and set NR as boolean parameter.. ?
#~ - Fussion isRepeatableField and isRepeatableSubfield using heritage (OOP)
#~ - searchANDReplace: una funcion que recorra todos los campos y subcampos dados y haga un cambio dado: Ver http://search.cpan.org/~petdance/MARC-Record-1.39_02/lib/MARC/Doc/Tutorial.pod#Changing_existing_fields
#~ - Function to migrate, for any TAG, ^9 to ^9

sub countMARCRecords {	# Adds an overhead of ~1,4s for each 1000 recs
	my ($iRecs) = @_;
	my $recordcount = 0;
	while ( my $iRec = $iRecs->next ) { 
		$recordcount++; 
	}
	#~ print $recordcount; exit 1;
	return $recordcount;
}

sub record2html {
	my $record = shift;
	my $output = '<span class="record">'."\n";
	$output .= "\t".'<span class="leader">'.'LDR  '.$record->leader()."</span>\n";
	my @fields = $record->fields();
	foreach my $field (@fields) {
		$output .= "\t".'<span class="field">';
		$output .= '<span class="tag">'. $field->tag()."</span>";
		if ($field->is_control_field()) {
			$output .= $field->data();
		} else {
			$output .= '<span class="indicators">';
			$output .= $field->indicator(1);
			$output .= $field->indicator(2);
			$output .= "</span>";
			my @subfields = $field->subfields();

			while (my $subfield = pop(@subfields)) {
				my ($code, $data) = @$subfield;
				$output .= '<span class="code">'.$code."</span>";
				 #~ if ( !defined($data)) { print $output; print $record->as_formatted(); print "\n-----\n"; }
				$output .= '<span class="data">'.$data."</span>";
			}

			#~ foreach my $subfield (@subfields) {
				#~ my ($code, $data) = @$subfield;	# ToDO: Ver qué pasa que a veces no se inicializa $data... ¿subcampo vacío..?
				#~ $output .= '<span class="code">'.$code."</span>";
				#~ $output .= '<span class="data">'.$data."</span>";
			#~ }
		}
		$output .= "</span>\n";	# /field
	}
	$output .= "</span>\n";	# /record
	return $output;
}

sub print2html { # Print side by side two records into HTML
	my ($iRec, $oRec) = @_;
	my $title = "Migration";
	my $output = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">'."\n";
	$output .= '<html>'."\n";
	$output .= '<head>'."\n";
	$output .= '<meta http-equiv="content-type" content="text/html; charset=UTF-8" />'."\n";
	$output .= "<title>$title</title>"."\n";
	$output .= '<link rel="stylesheet" type="text/css" href="mig.css" />'."\n";
	$output .= '</head>'."\n";
	$output .= '<body>'."\n";
	$output .= '<div id="container">';
	$output .= ' <div id="row">';
	$output .= '  <div id="left">'. record2html($iRec). '</div>'."\n";
	$output .= '  <div id="rigt">'. record2html($oRec). '</div>'."\n";
	$output .= ' </div>';
	$output .= '</div>';
	$output .= '</body>'."\n";
	$output .= '</html>'."\n";
	return $output;
}

sub print2txt {
#OPENISIS:	TAG<tab>ind1ind2^aData.. (el LDR directly at the begins, without heeaderdirectamente)
#MRK:			=TAG<spc><spc>ind1ind2^aData.. (o LDR en vez de TAG)
#YAZ:			
	my ($record, $mode) = @_;
	if ( $mode eq "openisis" ) {
		my $output .= "".$record->leader()."\n"; # Remove if necessary
		my @fields = $record->fields();
		foreach my $field (@fields) {
			$output .= "". int($field->tag())."\t";	# With int(), "8" instead of "008"
			if ($field->is_control_field()) {
				$output .= $field->data();
			} else {
				$output .= $field->indicator(1);
				$output .= $field->indicator(2);
				my @subfields = $field->subfields();

				while (my $subfield = pop(@subfields)) {
					my ($code, $data) = @$subfield;
					$output .= '^'.$code."";
					if ( $code =~ m/[0-9a-z]/i ) {
						$code = "9";
					}
					if ( not defined $data ) {
						$data = "[err4]";
					}
					#~ if ( !defined($data)) { print $output; print $record->as_formatted(); print "\n-----\n"; }
					$output .= "".$data."";
				}
				
				#~ foreach my $subfield (@subfields) {
					#~ my ($code, $data) = @$subfield;	# ToDO: Ver qué pasa que a veces no se inicializa $data... ¿subcampo vacío..?
					#~ $output .= '^'.$code."";
					#~ $output .= "".$data."";	# data($subfield); ?
				#~ }
			}
			$output .= "\n";	# /field
		}
		$output .= "\n";	# /record
		return $output;
	} elsif ($mode eq "MRK") {
		#TODO: IDEM, but for MRK... 
	} else {
		die "$mode is an invalid print2txt mode! Options are \"openisis\" and \"MRK\". Exiting";	# TODO: marc breaker output..? marcdump output?
		return die;
	}
}

sub changeLeader {
	my ($leader, $pos, $new_value) = @_;

	#~ http://search.cpan.org/~gmcharlt/MARC-Record-2.0.6/lib/MARC/Doc/Tutorial.pod#Changing_a_record%27s_leader
	substr($leader, $pos, 1, substr($new_value,0,1) ); 

	return $leader;
}

sub moveSubfields  {
	my ($iRec, $oRec, $iField, $iSubfield, $oField, $oSubfield) = @_;
	my @fields = $iRec->field( $iField );
	foreach my $field ( @fields ) {
		my $subfield_data = $field->subfield( $iSubfield );

		#~ my $ind1 = "";
		#~ my $ind2 = "";
		#~ if ( defined($field->indicator(1)) and ($field->indicator(1)  =~ m/^[0-9]$/) ) { $ind1 = $field->indicator(1); }
		#~ if ( defined($field->indicator(2)) and ($field->indicator(2)  =~ m/^[0-9]$/) ) { $ind2 = $field->indicator(2); }

		if ( defined($subfield_data) and $subfield_data ne '' ) {# 	if ( $subfield_data ) {	#	Unfortunately this will be false when $name = 0;
			my $newField = MARC::Field->new( 
				$oField,
				$field->indicator(1),
				$field->indicator(2),
				$oSubfield => $field->subfield( $iSubfield )
			);
			#~ $oRec->append_fields($newField);
			$oRec->insert_grouped_field($newField);
		}
	}
	return $oRec;
}

sub moveSubfields_NR  {
# Sólo copia la primer ocurrencia, porque no debería haber más de una en el registro de entrada.
# ¿Devuelve error si encuentra más de una...? NO
	my ($iRec, $oRec, $iField, $iSubfield, $oField, $oSubfield) = @_;
	my @fields = $iRec->field( $iField );
	my $count = 0;
	foreach my $field ( @fields ) {
		if ( $count == 0 ) {
			my $subfield_data = $field->subfield( $iSubfield );
			if ( defined($subfield_data) and $subfield_data ne '' ) { # if ( $subfield_data ) {	#	Unfortunately this will be false when $name = 0;
				my $newField = MARC::Field->new( 
					$oField,
					$field->indicator(1),
					$field->indicator(2),
					$oSubfield => $field->subfield( $iSubfield )
				);
				$oRec->insert_grouped_field($newField);
			}
		} else {
			#~ TODO WARNING Only one ocurrence from input field expected!!
			;
		}
		$count++;
	}
	return $oRec;
}

sub sortTAGs { # given a record, sort its TAGs
	my ($unsorted_record) = @_;
	my $sorted_record = MARC::Record->new();
	$sorted_record->insert_fields_ordered( $unsorted_record->fields() );
	return $sorted_record;
	#$_[0] = $sorted_record;
}


#~ ToDo: Finish this method
sub sortSubfields {	#~ Sort subfields by subfield indicators. You can optionally specify an order as string of subfield codes.
	#~ http://cpansearch.perl.org/src/VOJ/PICA-Record-0.584/lib/PICA/Field.pm
    my ($self, $order) = @_;
    return unless @{$self->{_subfields}};
    $order = "" unless defined $order;

    my (%pos,$i);
    for (split('',$order.'0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ')) {
        $pos{$_} = $i++ unless defined $pos{$_};
    }

    my @sf = @{$self->{_subfields}};
    my $n = @sf / 2 - 1;
    my @sorted = ();

    @sorted = sort { 
        $pos{$sf[2*$a]} <=> $pos{$sf[2*$b]}
    } (0..$n);

    $self->{_subfields} = [ map { $sf[2*$_] => $sf[2*$_+1] } @sorted ];
}


sub marc_2_GZiped_b64 {
	# MARC record object to gziped base 64 string
	my ($Rec) = @_;
	my $recXML = $Rec->as_xml();
	my $recGZiped = "";
	gzip \$recXML => \$recGZiped
		or die "gzip failed: $GzipError\n";
	my $recGZiped_b64 = encode_base64( $recGZiped );
	#print length($irecXML), " - LengthGZb64: ", length($irecGZiped_b64), " (", int( length($irecGZiped_b64) / int( length($irecXML) ) * 100 ), "%) - Id: ", $count, "\n";
	return $recGZiped_b64;
	#EXAMPLES:
	#print GZiped_b64_2_marcXML( marc_2_GZiped_b64( $irec ) ), "\n";	# convert one direction an the other
}

sub GZiped_b64_2_marcXML {
	# Gziped base 64 string to XML MARC record string (not an object)
	my ($Rec) = @_;
	my $recGZiped = decode_base64($Rec);
	my $recXML = "";
	gunzip \$recGZiped => \$recXML
		or die "gunzip failed: $GzipError\n";
	return $recXML;
}

sub iso3166_to_marc {	# Convert from two-letter (lowercase) codes from ISO 3166-1 to a MARC country code place (http://www.loc.gov/marc/unimarctomarc21_tables.pdf).
	my $country_ISO = shift;

	# ToDo: Verify if is in @codes   = all_country_codes( LOCALE_CODE_ALPHA_2 );  with ~~ smartmatch
  
	my %countries = (
		"AD" => "an ", 
		"AE" => "ts ", 
		"AF" => "af ", 
		"AG" => "aq ", 
		"AL" => "aa ", 
		"AN" => "na ", 
		"AO" => "ao ", 
		"AQ" => "ay ", 
		"AR" => "ag ", 
		"AS" => "as ", 
		"AT" => "au ", 
		"AU" => "at ", 
		"BB" => "bb ", 
		"BD" => "bg ", 
		"BE" => "be ", 
		"BG" => "bu ", 
		"BH" => "ba ", 
		"BI" => "bd ", 
		"BJ" => "dm ", 
		"BM" => "bm ", 
		"BN" => "cc ", 
		"BN" => "bx ", 
		"BO" => "bo ", 
		"BR" => "bl ", 
		"BS" => "bf ", 
		"BT" => "bt ", 
		"BU" => "br ", 
		"BV" => "bv ", 
		"BW" => "bs ", 
		"BY" => "bw ", 
		"BZ" => "bh ", 
		"CA" => "xxc", 
		"CC" => "xb ", 
		"CF" => "cx ", 
		"CG" => "cf ", 
		"CH" => "sz ", 
		"CI" => "iv ", 
		"CK" => "cw ", 
		"CL" => "cl ", 
		"CM" => "cm ", 
		"CO" => "ck ", 
		"CR" => "cr ", 
		"CT" => "cp ", 
		"CU" => "cu ", 
		"CV" => "cv ", 
		"CX" => "xa ", 
		"CY" => "cy ", 
		"CZ" => "xr ", 
		"DE" => "gw ", 
		"DJ" => "ft ", 
		"DK" => "dk ", 
		"DM" => "dq ", 
		"DO" => "dr ", 
		"DZ" => "ae ", 
		"EC" => "ec ", 
		"EG" => "ua ", 
		"EH" => "ss ", 
		"ES" => "sp ", 
		"ET" => "et ", 
		"FI" => "fi ", 
		"FJ" => "fj ", 
		"FK" => "fk ", 
		"FO" => "fa ", 
		"FQ" => "fs ", 
		"FR" => "fr ", 
		"GA" => "go ", 
		"GB" => "xxk", 
		"GD" => "gd ", 
		"GF" => "fg ", 
		"GH" => "gh ", 
		"GI" => "gi ", 
		"GL" => "gl ", 
		"GM" => "gm ", 
		"GN" => "gv ", 
		"GP" => "gp ", 
		"GQ" => "eg ", 
		"GR" => "gr ", 
		"GT" => "gt ", 
		"GU" => "gu ", 
		"GW" => "pg ", 
		"GY" => "gy ", 
		"HK" => "hk ", 
		"HM" => "hm ", 
		"HN" => "ho ", 
		"HT" => "ht ", 
		"HU" => "hu ", 
		"HV" => "uv ", 
		"ID" => "io ", 
		"IE" => "ie ", 
		"IL" => "is ", 
		"IN" => "ii ", 
		"IO" => "bi ", 
		"IQ" => "iq ", 
		"IR" => "ir ", 
		"IS" => "ic ", 
		"IT" => "it ", 
		"JM" => "jm ", 
		"JO" => "jo ", 
		"JP" => "ja ", 
		"JT" => "ji ", 
		"KE" => "ke ", 
		"KH" => "cb ", 
		"KI" => "gb ", 
		"KM" => "cq ", 
		"KN" => "xd ", 
		"KP" => "kn ", 
		"KR" => "ko ", 
		"KW" => "ku ", 
		"KY" => "cj ", 
		"LA" => "ls ", 
		"LB" => "le ", 
		"LC" => "xk ", 
		"LI" => "lh ", 
		"LK" => "ce ", 
		"LR" => "lb ", 
		"LS" => "lo ", 
		"LU" => "lu ", 
		"LY" => "ly ", 
		"MA" => "mr ", 
		"MC" => "mc ", 
		"MG" => "mg ", 
		"MI" => "xf ", 
		"ML" => "ml ", 
		"MN" => "mp ", 
		"MO" => "mh ", 
		"MQ" => "mq ", 
		"MR" => "mu ", 
		"MS" => "mj ", 
		"MT" => "mm ", 
		"MU" => "mf ", 
		"MV" => "xc ", 
		"MW" => "mw ", 
		"MX" => "mx ", 
		"MY" => "my ", 
		"MZ" => "mz ", 
		"NA" => "sx ", 
		"NC" => "nl ", 
		"NE" => "ng ", 
		"NF" => "nx ", 
		"NG" => "nr ", 
		"NL" => "ne ", 
		"NO" => "no ", 
		"NP" => "np ", 
		"NQ" => "ay ", 
		"NR" => "nu ", 
		"NT" => "iy ", 
		"NU" => "xh ", 
		"NV" => "uc ", 
		"NZ" => "nz ", 
		"OM" => "mk ", 
		"PA" => "pn ", 
		"PC" => "tt ", 
		"PE" => "pe ", 
		"PF" => "fp ", 
		"PG" => "pp ", 
		"PH" => "ph ", 
		"PI" => "pf ", 
		"PK" => "pk ", 
		"PL" => "pl ", 
		"PM" => "xl ", 
		"PN" => "pc ", 
		"PR" => "pr ", 
		"PT" => "po ", 
		"PU" => "up ", 
		"PY" => "py ", 
		"QA" => "qa ", 
		"RE" => "re ", 
		"RH" => "rh ", 
		"RO" => "rm ", 
		"RW" => "rw ", 
		"SA" => "su ", 
		"SB" => "bp ", 
		"SC" => "se ", 
		"SD" => "sj ", 
		"SE" => "sw ", 
		"SG" => "si ", 
		"SH" => "xj ", 
		"SI" => "xv ", 
		"SI" => "xp ", 
		"SJ" => "sb ", 
		"SK" => "xo ", 
		"SL" => "sl ", 
		"SM" => "sm ", 
		"SN" => "sg ", 
		"SO" => "so ", 
		"SR" => "sr ", 
		"ST" => "sf ", 
		"SU" => "xx ", 
		"SV" => "es ", 
		"SY" => "sy ", 
		"SZ" => "sq ", 
		"TC" => "tc ", 
		"TD" => "cd ", 
		"TG" => "tg ", 
		"TH" => "th ", 
		"TK" => "tl ", 
		"TN" => "ti ", 
		"TO" => "to ", 
		"TP" => "io ", 
		"TR" => "tu ", 
		"TT" => "tr ", 
		"TV" => "tv ", 
		"TW" => "ch ", 
		"TZ" => "tz ", 
		"UA" => "un ", 
		"UG" => "ug ", 
		"US" => "xxu", 
		"UY" => "uy ", 
		"VA" => "vc ", 
		"VC" => "xm ", 
		"VE" => "ve ", 
		"VG" => "vb ", 
		"VI" => "vi ", 
		"VN" => "vm ", 
		"VU" => "nn ", 
		"WF" => "wf ", 
		"WK" => "wk ", 
		"WS" => "ws ", 
		"XV" => "vp ", 
		"YD" => "ys ", 
		"YE" => "ye ", 
		"YU" => "yu ", 
		"ZA" => "sa ", 
		"ZM" => "za ", 
		"ZR" => "cg ", 
		"ZW" => "rh "
	);
	#~ return ;	# This here...?

	if (exists $countries{ uc($country_ISO) }) {
		return $countries{ uc($country_ISO) };
	} else {
		return "|||";
	}
}

sub getTitleSecondIndicator {
	#~ Receive title text, return number of int of second indicator

	my $title = shift;
	my $firstWord = "";
	#~ $title =~ /^(.*?)\s/;	# Extract first word of title
	($firstWord) = $title =~ /\A([^:\s]+)/;
	$firstWord = uc( $1 );

	#~ print $firstWord."   de   ".$title."\n";
 
	my @stopwords = (
		"A", 
		"ABT", 
		"AL", 
		"ALS", 
		"AN", 
		"AND", 
		"AS", 
		"AT", 
		"AU", 
		"AUF", 
		"AUS", 
		"AUX", 
		"AVEC", 
		"B", 
		"BEI", 
		"BIS", 
		"BY", 
		"C", 
		"COMO", 
		"CON", 
		"DANS", 
		"DAS", 
		"DE", 
		"DEI", 
		"DEL", 
		"DEM", 
		"DEN", 
		"DER", 
		"DES", 
		"DIE", 
		"DU", 
		"E", 
		"EIN", 
		"EINE", 
		"EL", 
		"EN", 
		"ET", 
		"FOER", 
		"FOR", 
		"FRA", 
		"FROM", 
		"FUER", 
		"FUR", 
		"IHRE", 
		"IM", 
		"IN", 
		"INTO", 
		"ITS", 
		"LA", 
		"LAS", 
		"LE", 
		"LES", 
		"LEUR", 
		"LOS", 
		"MIT", 
		"OF", 
		"ON", 
		"OU", 
		"PAR", 
		"PARA", 
		"PART", 
		"PARTE", 
		"PARTIE", 
		"PARTS", 
		"PER", 
		"POR", 
		"POUR", 
		"QUE", 
		"SEC", 
		"SECTION", 
		"SERIE", 
		"SERIES", 
		"SES", 
		"SI", 
		"SIN", 
		"SOBRE", 
		"SOUS", 
		"SU", 
		"SUR", 
		"SUS", 
		"TE", 
		"TEIL", 
		"THE", 
		"TO", 
		"UBER", 
		"UN", 
		"UNA", 
		"UNAS", 
		"UND", 
		"UNDER", 
		"UNOS", 
		"UPON", 
		"VAN", 
		"VON", 
		"WITH", 
		"ZU", 
		"ZUR"
	);

	if ( ( $firstWord ~~ @stopwords ) && ( length($firstWord) < 9 ) ) {
		 #~ print $firstWord."\t".length($firstWord)."\n";
		return (length($firstWord)+1);
	} else {
		return "0";
	}
}

sub isRepeatableField {
	# NOTE IMPLEMENTED YET, CODE BELOW IS JUST TO HELP START CODING
	my ($iRec, $oRec, $iField, $iSubfield, $oField, $oSubfield) = @_;
	my @fields = $iRec->field( $iField );
	foreach my $field ( @fields ) {
		my $subfield_data = $field->subfield( $iSubfield );
		if ( defined($subfield_data) and $subfield_data ne '' ) {# 	if ( $subfield_data ) {	#	Unfortunately this will be false when $name = 0;
			my $newField = MARC::Field->new( 
				$oField,
				$field->indicator(1),
				$field->indicator(2),
				$oSubfield => $field->subfield( $iSubfield )
			);
			#~ $oRec->append_fields($newField);
			$oRec->insert_grouped_field($newField);
		}
	}
	return $oRec;
}

sub isRepeatableSubfield {
	my ($iRec, $oRec, $iField, $iSubfield, $oField, $oSubfield) = @_;
	return 0;
}
1;

__END__

=head1 NAME

PABLOAB::Marcgyver - Perl extension for handling MARC records

=head1 VERSION

version 0.001

=head1 SYNOPSIS
#
  use Marcgyver::Field;
  my $field = PICA::Field->new( '028A',
    '9' => '117060275',
    '8' => 'Martin Schrettinger'
  );

  $field->add( 'd' => 'Martin', 'a' => 'Schrettinger' );
  $field->update( "8", "Schrettinger, Martin" );

  print $field->normalized;
  print $field->xml;

=head1 DESCRIPTION

#Defines PICA+ fields for use in the PICA::Record module.

=head1 EXPORT

#The method C<parse_pp_tag> is exported.

=head1 METHODS

=head2 new ( [...] )

The constructor, which will return a C<PICA::Field> object or croak on error.
You can call the constructor with a tag and a list of subfields:

  PICA::Field->new( '028A',
    '9' => '117060275',
    '8' => 'Martin Schrettinger'
  );

With a string of normalized PICA+ data of one field:

  PICA::Field->new("\x1E028A \x1F9117060275\x1F8Martin Schrettinger\x0A');

With a string of readable PICA+ data:

  PICA::Field->new('028A $9117060275$8Martin Schrettinger');

=head2 copy ( $field )

Creates and returns a copy of this object.

=head2 parse ( $string, [, \&tag_filter_func ] )

The constructur will return a PICA::Field object based on data that is 
parsed if null if the filter dropped the field. Dropped fields will not 
be parsed so they are also not validated.

The C<$tag_filter_func> is an optional reference to a user-supplied 
function that determines on a tag-by-tag basis if you want the tag to 
be parsed or dropped. The function is passed the tag number (including 
occurrence), and must return a boolean. 

For example, if you only want to 021A fields, try this:

The filter function can be used to select only required fields

   sub filter {
        my $tagno = shift;
        return $tagno eq "021A";
    }
    my $field = PICA::Field->parse( $string, \&filter );

=head2 tag ( [ $tag ] )

Returns the PICA+ tag and occurrence of the field. Optionally sets tag (and occurrence) to a new value.

=head2 occurrence ( [ $occurrence ] ) or occ ( ... )

Returns the ocurrence or undef. Optionally sets the ocurrence to a new value.

=head2 level ( )

Returns the level (0: main, 1: local, 2: copy) of this field.

=head2 subfield ( [ $code(s) ] ) or sf ( ... )

Return selected or all subfield values. If you specify 
one ore more subfield codes, only matching subfields are 
returned. When called in a scalar context returns only the
first (matching) subfield. You may specify multiple subfield codes:

    my $subfield = $field->subfield( 'a' );   # first $a
    my $subfield = $field->subfield( 'acr' ); # first of $a, $c, $r
    my $subfield = $field->subfield( 'a', 'c', 'r' ); # the same

    my @subfields = $field->subfield( '0-9' );     # $0 ... $9
    my @subfields = $field->subfield( qr/[0-9]/ ); # $0 ... $9

    my @subfields = $field->subfield( 'a' );
    my @all_subfields = $field->subfield();

If no matching subfields are found, C<undef> is returned in a scalar
context or an empty list in a list context.

Remember that there can be more than one subfield of a given code!

=head2 content ( [ $code(s) ] )

Return selected or all subfields as an array of arrays. If you specify 
one ore more subfield codes, only matching subfields are returned. See
the C<subfield> method for more examples.

This shows the subfields from a 021A field:

        [
          [ 'a', '@TraitÃ© de documentation' ],
          [ 'd', 'Le livre sur le livre ; ThÃ©orie et pratique' ],
          [ 'h', 'Paul Otlet' ]
        ]

=head2 add ( $code, $value [, $code, $value ...] )

Adds subfields to the end of the subfield list.
Whitespace in subfield values is normalized.

    $field->add( 'c' => '1985' );

Returns the number of subfields added. 

=head2 update ( $sf => $value [ $sf => $value ...] )

Allows you to change the values of the field for one or more given subfields:

  $field->update( a => 'Little Science, Big Science' );

If you attempt to update a subfield which does not currently exist in the field,
then a new subfield will be appended. If you don't like this auto-vivification
you must check for the existence of the subfield prior to update.

  if ( defined $field->subfield( 'a' ) ) {
      $field->update( 'a' => 'Cryptonomicon' );
  }

Instead of a single value you can also pass an array reference. The following
statements should have the same result:

  $field->update( 'x', 'foo', 'x', 'bar' );
  $field->update( 'x' => ['foo', 'bar'] );

To remove a subfield, update it to undef or an empty array reference:

  $field->update( 'a' => undef );
  $field->update( 'a' => [] );

=head2 replace ( $field | ... )

Allows you to replace an existing field with a new one. You may pass a
C<PICA::Field> object or parameters for a new field to replace the
existing field with. Replace does not return a meaningful or reliable value.

=head2 empty_subfields ( )

Returns a list of all codes of empty subfields.

=head2 empty ( )

Test whether there are no subfields or all subfields are empty. This method 
is automatically called by overloading whenever a PICA::Field is converted 
to a boolean value.

=head2 purged ( )

Remove a copy of this field with empty subfields
removed or undef if the whole field is empty.

=head2 normalized ( [$subfields] )

Returns the field as a string. The tag number, occurrence and 
subfield indicators are included. 

If C<$subfields> is specified, then only those subfields will be included.

=head2 sort ( [ $order ] )

Sort subfields by subfield indicators. You can optionally specify an order as string of subfield codes.

=head2 size

Returns the number of subfields (no matter if empty or not).

=head2 string ( [ %params ] )

Returns a pretty string for printing.

Returns the field as a string. The tag number, occurrence and 
subfield indicators are included. 

If C<subfields> is specified, then only those subfields will be included.

Fields without subfields return an empty string.

=head2 xml ( [ [ writer => ] $writer | [ OUTPUT ] => \$sref | %param ] )

Return the field in PICA-XML format or write it to an L<XML::Writer>
and return the writer. If you provide parameters, they will be passed
to a newly created XML::Writer that is used to write to a string.

By default the PICA-XML namespaces with namespace prefix 'pica' is 
included. In addition to XML::Writer this methods knows the 'header'
parameter that first adds the XML declaration.

=head2 html ( [ %options ] )

Returns a HTML representation of the field for browser display. See also
the C<pica2html.xsl> script to generate a more elaborated HTML view from
PICA-XML.

=head1 STATIC METHODS

=head2 parse_pp_tag tag ( $tag )

Tests whether a string can be used as a tag/occurrence specifier. A tag
indicator consists of a 'type' (00-99) and an 'indicator' (A-Z and @),
both conflated as the 'tag', and an optional occurrence (00-99). This
method returns a list of two values: occurrence and tag (this order!).
It can be used to parse and test tag specifiers this ways:

  ($occurrence, $tag) = parse_pp_tag( $t );
  parse_pp_tag( $t ) or print STDERR "Not a valid tag: $t\n";

=head1 SEE ALSO

This module was inspired by L<MARC::Field> by Andy Lester.

=encoding utf-8

=head1 AUTHOR

Pablo Bianchi <pablo.bianchi@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Pablo Bianchi.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

	#~ foreach my $field ( $iRec->field( $iField ); ) {
		#~ if ( defined($field->subfield( $iSubfield )) and $field->subfield( $iSubfield ) ne '' ) {
			#~ my $newField = MARC::Field->new($oField, $field->indicator(1), $field->indicator(2), $oSubfield => $field->subfield( $iSubfield);
			#~ $oRec->append_fields($newField);
		#~ }
	#~ }
