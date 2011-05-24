################################################################################
# $Id: dau.pl 273 2008-02-03 15:27:25Z heidinger $
################################################################################
#
# dau.pl - write like an idiot
#
################################################################################
# Author
################################################################################
#
# Clemens Heidinger <heidinger@dau.pl>
#
################################################################################
# Changelog
################################################################################
#
# dau.pl has a built-in changelog (--changelog switch)
#
################################################################################
# Credits
################################################################################
#
# - Robert Hennig: For the original dau shell script. Out of this script,
#   merged with some other small Perl and shell scripts and aliases arised the
#   first version of dau.pl for irssi.
#
################################################################################
# Documentation
################################################################################
#
# dau.pl has a built-in documentation (--help switch)
#
################################################################################
# License
################################################################################
#
# Licensed under the BSD license
#
################################################################################
# Website
################################################################################
#
# http://dau.pl/
#
# Additional information, DAU.pm, the dauomat and the dauproxy
#
################################################################################

use 5.6.0;
use File::Basename;
use File::Path;
use IPC::Open3;
use Irssi 20021107.0841;
use Irssi::TextUI;
use locale;
use POSIX;
use re 'eval';
use strict;
use Tie::File;
use vars qw($VERSION %IRSSI);

$VERSION = '2.4.3';
#$VERSION = '2.4.3 SVN ($LastChangedRevision: 273 $)';
%IRSSI = (
          authors     => 'Clemens Heidinger',
          changed     => '$LastChangedDate: 2008-02-03 16:27:25 +0100 (Sun, 03 Feb 2008) $',
          commands    => 'dau',
          contact     => 'heidinger@dau.pl',
          description => 'write like an idiot',
          license     => 'BSD',
          modules     => 'File::Basename File::Path IPC::Open3 POSIX Tie::File',
          name        => 'DAU',
          sbitems     => 'daumode',
          url         => 'http://dau.pl/',
);

################################################################################
# Register commands
################################################################################

Irssi::command_bind('dau', \&command_dau);

################################################################################
# Register settings
# setting changed/added => change/add it here
################################################################################

# boolean
Irssi::settings_add_bool('misc', 'dau_away_quote_reason', 1);
Irssi::settings_add_bool('misc', 'dau_away_reminder', 0);
Irssi::settings_add_bool('misc', 'dau_babble_verbose', 1);
Irssi::settings_add_bool('misc', 'dau_color_choose_colors_randomly', 1);
Irssi::settings_add_bool('misc', 'dau_cowsay_print_cow', 0);
Irssi::settings_add_bool('misc', 'dau_figlet_print_font', 0);
Irssi::settings_add_bool('misc', 'dau_silence', 0);
Irssi::settings_add_bool('misc', 'dau_statusbar_daumode_hide_when_off', 0);
Irssi::settings_add_bool('misc', 'dau_tab_completion', 1);

# Integer
Irssi::settings_add_int('misc', 'dau_babble_history_size', 10);
Irssi::settings_add_int('misc', 'dau_babble_verbose_minimum_lines', 2);
Irssi::settings_add_int('misc', 'dau_cool_maximum_line', 2);
Irssi::settings_add_int('misc', 'dau_cool_probability_eol', 20);
Irssi::settings_add_int('misc', 'dau_cool_probability_word', 20);
Irssi::settings_add_int('misc', 'dau_remote_babble_interval_accuracy', 90);

# String
Irssi::settings_add_str('misc', 'dau_away_away_text', '$N is away now: [ $reason ]. Away since: $Z. I am currently not available at $T @ $chatnet (sry 4 amsg)!');
Irssi::settings_add_str('misc', 'dau_away_back_text', '$N is back: [ $reason ]. Away time: [ $time ]. I am available again at $T @ $chatnet (sry 4 amsg)!');
Irssi::settings_add_str('misc', 'dau_away_options',
                                                   "--parse_special --bracket -left '!---?[' -right ']?---!' --color -split capitals -random off -codes 'light red; yellow',"  .
                                                   "--parse_special --bracket -left '--==||{{' -right '}}||==--' --color -split capitals -random off -codes 'light red; light cyan'," .
                                                   "--parse_special --bracket -left '--==||[[' -right ']]||==--' --color -split capitals -random off -codes 'yellow; light green'"
);
Irssi::settings_add_str('misc', 'dau_away_reminder_interval', '1 hour');
Irssi::settings_add_str('misc', 'dau_away_reminder_text', '$N is still away: [ $reason ]. Away time: [ $time ] (sry 4 amsg)');
Irssi::settings_add_str('misc', 'dau_babble_options_line_by_line', '--nothing');
Irssi::settings_add_str('misc', 'dau_babble_options_preprocessing', '');
Irssi::settings_add_str('misc', 'dau_color_codes', 'blue; green; red; magenta; yellow; cyan');
Irssi::settings_add_str('misc', 'dau_cool_eol_style', 'random');
Irssi::settings_add_str('misc', 'dau_cowsay_cowlist', '');
Irssi::settings_add_str('misc', 'dau_cowsay_cowpath', &def_dau_cowsay_cowpath);
Irssi::settings_add_str('misc', 'dau_cowsay_cowpolicy', 'allow');
Irssi::settings_add_str('misc', 'dau_cowsay_cowsay_path', &def_dau_cowsay_cowsay_path);
Irssi::settings_add_str('misc', 'dau_cowsay_cowthink_path', &def_dau_cowsay_cowthink_path);
Irssi::settings_add_str('misc', 'dau_daumode_channels', '');
Irssi::settings_add_str('misc', 'dau_delimiter_string', ' ');
Irssi::settings_add_str('misc', 'dau_figlet_fontlist', 'mnemonic,term,ivrit');
Irssi::settings_add_str('misc', 'dau_figlet_fontpath', &def_dau_figlet_fontpath);
Irssi::settings_add_str('misc', 'dau_figlet_fontpolicy', 'allow');
Irssi::settings_add_str('misc', 'dau_figlet_path', &def_dau_figlet_path);
Irssi::settings_add_str('misc', 'dau_files_away', '.away');
Irssi::settings_add_str('misc', 'dau_files_babble_messages', 'babble_messages');
Irssi::settings_add_str('misc', 'dau_files_cool_suffixes', 'cool_suffixes');
Irssi::settings_add_str('misc', 'dau_files_root_directory', "$ENV{HOME}/.dau");
Irssi::settings_add_str('misc', 'dau_files_substitute', 'substitute.pl');
Irssi::settings_add_str('misc', 'dau_language', 'en');
Irssi::settings_add_str('misc', 'dau_moron_eol_style', 'random');
Irssi::settings_add_str('misc', 'dau_parse_special_list_delimiter', ' ');
Irssi::settings_add_str('misc', 'dau_random_options',
                                                      '--substitute --boxes --uppercase,' .
                                                      "--substitute --color -split capitals -random off -codes 'light red; yellow'," .
                                                      "--substitute --color -split capitals -random off -codes 'light red; light cyan'," .
                                                      "--substitute --color -split capitals -random off -codes 'yellow; light green'," .
                                                      '--substitute --color --uppercase,' .
                                                      '--substitute --cool,' .
                                                      '--substitute --delimiter,' .
                                                      '--substitute --dots --moron,' .
                                                      '--substitute --leet,' .
                                                      '--substitute --mix,' .
                                                      '--substitute --mixedcase --bracket,' .
                                                      '--substitute --moron --stutter --uppercase,' .
                                                      '--substitute --moron -omega on,' .
                                                      '--substitute --moron,' .
                                                      '--substitute --uppercase --underline,' .
                                                      '--substitute --words --mixedcase'
);
Irssi::settings_add_str('misc', 'dau_remote_babble_channellist', '');
Irssi::settings_add_str('misc', 'dau_remote_babble_channelpolicy', 'deny');
Irssi::settings_add_str('misc', 'dau_remote_babble_interval', '1 hour');
Irssi::settings_add_str('misc', 'dau_remote_channellist', '');
Irssi::settings_add_str('misc', 'dau_remote_channelpolicy', 'deny');
Irssi::settings_add_str('misc', 'dau_remote_deop_reply', 'you are on my shitlist now @ $nick');
Irssi::settings_add_str('misc', 'dau_remote_devoice_reply', 'you are on my shitlist now @ $nick');
Irssi::settings_add_str('misc', 'dau_remote_op_reply', 'thx 4 op @ $nick');
Irssi::settings_add_str('misc', 'dau_remote_permissions', '000000');
Irssi::settings_add_str('misc', 'dau_remote_question_regexp', '%%%DISABLED%%%');
Irssi::settings_add_str('misc', 'dau_remote_question_reply', 'EDIT_THIS_ONE');
Irssi::settings_add_str('misc', 'dau_remote_voice_reply', 'thx 4 voice @ $nick');
Irssi::settings_add_str('misc', 'dau_standard_messages', 'hi @ all');
Irssi::settings_add_str('misc', 'dau_standard_options', '--random');
Irssi::settings_add_str('misc', 'dau_words_range', '1-4');

################################################################################
# Register signals
# (Note that most signals are set dynamical in the subroutine signal_handling)
################################################################################

Irssi::signal_add_last('setup changed', \&signal_setup_changed);
Irssi::signal_add_last('window changed' => sub { Irssi::statusbar_items_redraw('daumode') });
Irssi::signal_add_last('window item changed' => sub { Irssi::statusbar_items_redraw('daumode') });

################################################################################
# Register statusbar items
################################################################################

Irssi::statusbar_item_register('daumode', '', 'statusbar_daumode');

################################################################################
# Global variables
################################################################################

# Timer used by --away

our %away_timer;

# babble

our %babble;

# --command -in

our $command_in;

# The command to use for the output (MSG f.e.)

our $command_out;

# '--command -out' used?

our $command_out_activated;

# Counter for the subroutines entered

our $counter_subroutines;

# Counter for the switches
# --me --moron: --me would be 0, --moron 1

our $counter_switches;

# daumode

our %daumode;

# daumode activated?

our $daumode_activated;

# Help text

our %help;
$help{options} = <<END;
%9--away%9
    Toggle away mode

    %9-channels%9 %U'#channel1/network1, #channel2/network2, ...'%U:
        Say away message in all those %Uchannels%U

    %9-interval%9 %Utime%U:
        Remind channel now and then that you're away

    %9-reminder%9 %Uon|off%U:
        Turn reminder on or off

%9--babble%9
    Babble a message.

    %9-at%9 %Unicks%U:
        Comma separated list of nicks to babble at.
        \$nick1, \$nick2 and so forth of the babble line will be replaced
        by those nicks.

    %9-cancel%9 %Uon|off%U:
        Cancel active babble

    %9-filter%9 %Uregular expression%U:
        Only let through if the babble matches the %Uregular expression%U

    %9-history_size%9 %Un%U:
        Set the size of the history for this one babble to %Un%U

%9--boxes%9
    Put words in boxes

%9--bracket%9
    Bracket the text

    %9-left%9 %Ustring%U:
        Left bracket

    %9-right%9 %Ustring%U:
        Right bracket

%9--changelog%9
    Print the changelog

%9--chars%9
    Only one character each line

%9--color%9
    Write in colors

    %9-codes%9 %Ucodes%U:
        Overrides setting dau_color_codes

    %9-random%9 %Uon|off%U:
        Choose color randomly from setting dau_color_codes resp.
        %9--color -codes%9 or take one by one in the exact order given.

    %9-split%9
        %Ucapitals%U:   Split by capitals
        %Uchars%U:      Every character another color
        %Ulines%U:      Every line another color
        %Uparagraph%U:  The whole paragraph in one color
        %Urchars%U:     Some characters one color
        %Uwords%U:      Every word another color

%9--command%9
    %9-in%9 %Ucommand%U:
        Feed dau.pl with the output (the public message)
        that %Ucommand%U produces

    %9-out%9 %Ucommand%U:
        %Utopic%U for example will set a dauified topic

%9--cool%9
    Be \$cool[tm]!!!!11one

    %9-eol_style%9 %Ustring%U:
        Override setting dau_cool_eol_style

    %9-max%9 %Un%U:
        \$Trademarke[tm] only %Un%U words per line tops

    %9-prob_eol%9 %U0-100%U:
        Probability that "!!!11one" or something like that will be put at EOL.
        Set it to 100 and every line will be.
        Set it to 0 and no line will be.

    %9-prob_word%9 %U0-100%U:
        Probability that a word will be \$trademarked[tm].
        Set it to 100 and every word will be.
        Set it to 0 and no word will be.

%9--cowsay%9
    Use cowsay to write

    %9-arguments%9 %Uarguments%U:
        Pass any option to cowsay, f.e. %U'-b'%U or %U'-e XX'%U.
        Look in the cowsay manualpage for details.

    %9-cow%9 %Ucow%U:
        The cow to use

    %9-think%9 %Uon|off%U:
        Thinking instead of speaking

%9--create_files%9
    Create files and directories of all dau_files_* settings

%9--daumode%9
    Toggle daumode.
    Works on a per channel basis!

    %9-modes_in%9 %Umodes%U:
        All incoming messages will be dauified and the
        specified modes are used by dau.pl.

    %9-modes_out%9 %Umodes%U:
        All outgoing messages will be dauified and the
        specified modes are used by dau.pl.

    %9-perm%9 %U[01][01]%U:
        Dauify incoming/outgoing messages?

%9--delimiter%9
    Insert a delimiter-string after each character

    %9-string%9 %Ustring%U:
        Override setting dau_delimiter_string. If this string
        contains whitespace, you should quote the string with
        single quotes.

%9--dots%9
    Put dots... after words...

%9--figlet%9
    Use figlet to write

    %9-font%9 %Ufont%U:
        The font to use

%9--help%9
    Print help

    %9-setting%9 %Usetting%U:
        More information about a specific setting

%9--leet%9
    Write in leet speech

%9--long_help%9
    Long help, i.e. examples, more about some features, ...

%9--me%9
    Send a CTCP ACTION instead of a PRIVMSG

%9--mix%9
    Mix all the characters in a word except for the first and last

%9--mixedcase%9
    Write in mixed case

%9--moron%9
    Write in uppercase, mix in some typos, perform some
    substitutions on the text, ... Just write like a
    moron

    %9-eol_style%9 %Ustring%U:
        Override setting dau_moron_eol_style

    %9-level%9 %Un%U:
        %Un%U gives the level of stupidity applied to text,
        the higher the stupider.
        %U0%U is the minimum, %U1%U currently only implemented for dau_language = de.

    %9-omega%9 %Uon|off%U:
        The fantastic omega mode

    %9-typo%9 %Uon|off%U:
        Mix in random typos

    %9-uppercase%9 %Uon|off%U:
        Uppercase text

%9--nothing%9
    Do nothing

%9--parse_special%9
    Parse for special metasequences and substitute them.

    %9-irssi_variables%9 %Uon|off%U:
        Parse irssi special variables like \$N

    %9-list_delimiter%9 %Ustring%U:
        Set the list delimiter used for \@nicks and \@opnicks to %Ustring%U.

    The special metasequences are:

    - \\n:
      real newline
    - \$nick1 .. \$nickN:
      N different randomly selected nicks
    - \@nicks:
      All nicks in channel
    - \$opnick1 .. \$opnickN:
      N different randomly selected opnicks
    - \@opnicks:
      All nicks in channel with operator status
    - \$?{ code }:
      the (perl)code will be evaluated and the last expression
      returned will replace that metasequence
    - irssis special variables like \$C for the current
      channel and \$N for your current nick

    Quoting:

    - \\\$: literal \$
    - \\\\: literal \\

%9--random%9
    Let dau.pl choose the options randomly. Get these options from the setting
    dau_random_options.

    %9-verbose%9 %Uon|off%U:
        Print what options --random has chosen

%9--reverse%9
    Reverse the input string

%9--stutter%9
    Stutter a bit

%9--substitute%9
    Apply own substitutions from file

%9--underline%9
    Underline text

%9--uppercase%9
    Write in upper case

%9--words%9
    Only a few words each line
END

# Containing irssi's 'cmdchars'

our $k = Irssi::parse_special('$k');

# Remember your nick mode

our %nick_mode;

# All the options

our %option;

# print() the message or not?

our $print_message;

# Queue holding the switches

our %queue;

# Remember the last switches used by --random so that they don't repeat

our $random_last;

# Signals

our %signal = (
    'complete word'     => 0,
    'daumode in'        => 0,
    'event 404'         => 0,
    'event privmsg'     => 0,
    'nick mode changed' => 0,
    'send text'         => 0,
);

# All switches that may be given at commandline
