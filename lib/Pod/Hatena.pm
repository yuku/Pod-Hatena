use 5.008;
use strict;
use warnings;

package Pod::Hatena;
# ABSTRACT: Convert POD to Hatena
use parent qw(Pod::Parser);
use Pod::ParseLink (); # core

sub initialize {
    my $self = shift;
    $self->SUPER::initialize(@_);
    $self->_private;
    $self;
}

sub _private {
    my $self = shift;
    $self->{_MyParser} ||= {
        Text      => [],       # final text
        Indent    => 0,        # list indent levels counter
        ListType  => '-',      # character on every item
        searching => ''   ,    # what are we searching for? (title, author etc.)
        sstack    => [] ,      # Stack for searching, needed for nested list
        format    => '',
        Title     => undef,    # page title
        Author    => undef,    # page author
    };
}

sub as_hatena {
    my ($parser, %args) = @_;
    my $data  = $parser->_private;
    my $lines = $data->{Text};
    my @header;
    if ($args{with_meta}) {
        @header = $parser->_build_hatena_head;
    }
    join("\n" x 2, @header, @{$lines}) . "\n";
}

sub _build_hatena_head {
    my $parser    = shift;
    my $data      = $parser->_private;
    return join "\n",
        map  { qq![[meta \l$_="$data->{$_}"]]! }
        grep { defined $data->{$_} }
        qw( Title Author );
}

# $prelisthead:
#   undef    : not list head
#   ''       : list head not huddled
#   otherwise: list head huddled
sub _save {
    my ($parser, $text, $prelisthead) = @_;
    my $data = $parser->_private;
    $text = $prelisthead."\n".$text if defined $prelisthead && $prelisthead ne '';
    push @{ $data->{Text} }, $text;
    return;
}

sub _unsave {
    my $parser = shift;
    my $data = $parser->_private;
    return pop @{ $data->{Text} };
}

sub _clean_text {
    my $text    = $_[1];
    my @trimmed = grep { $_; } split(/\n/, $text);

    return wantarray ? @trimmed : join("\n", @trimmed);
}

sub _escape {
    my $self = shift;
    local $_ = shift;

    return $_ if $self->_private->{format} eq 'text';

    # escape unordered lists and blockquotes
    s/^([-+*|])/\\$1/mg;

    if ($self->_private->{format} ne 'html') {
        s/([^\\]|^)</$1&lt;/mg;
        s/([^\\]|^)>/$1&gt;/mg;
    }

    return $_;
}

sub command {
    my ($parser, $command, $paragraph, $line_num) = @_;
    my $data = $parser->_private;

    # cleaning the text
    $paragraph = $parser->_clean_text($paragraph);

    # is it a header ?
    if ($command =~ m{head(\d)}xms) {
        my $level = $1;

        $paragraph = $parser->_escape_and_interpolate($paragraph, $line_num);

        # the headers never are indented
        $parser->_save($parser->format_header($level, $paragraph));
        if ($level == 1) {
            if ($paragraph =~ m{NAME}xmsi) {
                $data->{searching} = 'title';
            } elsif ($paragraph =~ m{AUTHOR}xmsi) {
                $data->{searching} = 'author';
            } else {
                $data->{searching} = '';
            }
        }
    }

    # opening a list ?
    elsif ($command =~ m{over}xms) {

        push @{$data->{sstack}}, $data->{searching};

    # closing a list ?
    } elsif ($command =~ m{back}xms) {

        $data->{searching} = pop @{$data->{sstack}};

    } elsif ($command =~ m{item}xms) {
        # this strips the POD list head; the searching=listhead will insert hatena's
        # FIXME: this does not account for named lists

        # Assuming that POD is correctly wrtitten, we just use POD list head as hatena's
        $data->{ListType} = '-'; # Default
        if($paragraph =~ m{^[ \t]* \* [ \t]*}xms) {
            $paragraph =~ s{^[ \t]* \* [ \t]*}{}xms;
        } elsif($paragraph =~ m{^[ \t]* (\d+\.) [ \t]*}xms) {
            $data->{ListType} = $1; # For numbered list only
            $paragraph =~ s{^[ \t]* \d+\. [ \t]*}{}xms;
        }

        if ($data->{searching} eq 'listpara') {
            $data->{searching} = 'listheadhuddled';
        }
        else {
            $data->{searching} = 'listhead';
        }

        if (length $paragraph) {
            $parser->textblock($paragraph, $line_num);
        }
    }

    # opening a format ?
    elsif ($command =~ m{begin}ms && $paragraph =~ /^(html|text)/) {

        $data->{format} = $1;
        push @{$data->{sstack}}, $data->{searching};

    # closing a format ?
    } elsif ($command =~ m{end}ms && $paragraph =~ /^(html|text)/) {

        $data->{format} = '' if $data->{format} eq $1;
        $data->{searching} = pop @{$data->{sstack}};

    }

    # ignore other commands
    return;
}

sub verbatim {
    my ($parser, $paragraph) = @_;

    # NOTE: perlpodspec says parsers should expand tabs by default
    # NOTE: Apparently Pod::Parser does not.  should we?
    # NOTE: this might be s/^\t/" " x 8/e, but what about tabs inside the para?

    my @lines = split /\n/, $paragraph;

    # smallest indentation
    my $smallest = 1024;
    foreach my $line ( @lines ) {
        next unless $line =~ m/^( +)/;
        $smallest = length($1) if length($1) < $smallest;
    }

    # cut $smallest length indentation from each line
    my $indent = ' ' x $smallest;
    foreach my $line ( @lines ) {
        $line =~ s/^$indent//;
    }

    if (@lines > 1) {
        unshift @lines, '>|?|';
        push @lines, '||<';
    }
    $paragraph = join "\n", @lines;

    $parser->_save($paragraph);
}

sub _escape_and_interpolate {
    my ($parser, $paragraph, $line_num) = @_;

    # escape hatena characters in text sequences except for inline code
    $paragraph = join '', $parser->parse_text(
        { -expand_text => '_escape_non_code' },
        $paragraph, $line_num
    )->raw_text;

    # interpolate the paragraph for embedded sequences
    $paragraph = $parser->interpolate($paragraph, $line_num);

    return $paragraph;
}

sub _escape_non_code {
    my ($parser, $text, $ptree) = @_;
    $text = $parser->_escape($text)
        unless $ptree->isa('Pod::InteriorSequence') && $ptree->cmd_name eq 'C';
    return $text;
}

sub textblock {
    my ($parser, $paragraph, $line_num) = @_;
    my $data = $parser->_private;
    my $prelisthead;

    $paragraph = $parser->_escape_and_interpolate($paragraph, $line_num);

    # clean the empty lines
    $paragraph = $parser->_clean_text($paragraph);

    # searching ?
    if ($data->{searching} =~ m{title|author}xms) {
        $data->{ ucfirst $data->{searching} } = $paragraph;
        $data->{searching} = '';
    } elsif ($data->{searching} =~ m{listhead(huddled)?$}xms) {
        my $is_huddled = $1;
        $paragraph = sprintf '%s %s', $data->{ListType}, $paragraph;
        if ($is_huddled) {
            # To compress into an item in order to avoid "\n\n" insertion.
            $prelisthead = $parser->_unsave();
        } else {
            $prelisthead = '';
        }
        $data->{searching} = 'listpara';
    } elsif ($data->{searching} eq 'listpara') {
        $data->{searching} = '';
    }

    # save the text
    $parser->_save($paragraph, $prelisthead);
}

sub interior_sequence {
    my ($self, $seq_command, $seq_argument, $pod_seq) = @_;

    # nested links are not allowed
    return sprintf '%s<%s>', $seq_command, $seq_argument
        if $seq_command eq 'L' && $self->_private->{InsideLink};

    return sprintf '%s<%s>', $seq_command, $seq_argument
        if $self->_private->{format} eq 'text';

    my $i = 2;
    my %interiors = (
        'I' => sub { return '<i>'    . $_[$i] . '</i>'    },  # italic
        'B' => sub { return '<b>'    . $_[$i] . '</b>'    },  # bold
        'C' => sub { return '<code>' . $_[$i] . '</code>' },  # monospace
        'F' => sub { return '<code>' . $_[$i] . '</code>' },  # system path
        # non-breaking space
        'S' => sub {
            (my $s = $_[$i]) =~ s/ /&nbsp;/g;
            return '<nobr>' . $s . '</nobr>';
        },
        'E' => sub {
            my $charname = $_[$i];
            return '&lt;' if $charname eq 'lt';
            return '&gt;' if $charname eq 'gt';
            return '|' if $charname eq 'verbar';
            return '/' if $charname eq 'sol';

            # convert legacy charnames to more modern ones (see perlpodspec)
            $charname =~ s/\A([lr])chevron\z/${1}aquo/;

            return "&#$1;" if $charname =~ /^0(x[0-9a-fA-Z]+)$/;

            $charname = oct($charname) if $charname =~ /^0\d+$/;

            return "&#$charname;"      if $charname =~ /^\d+$/;

            return "&$charname;";
        },
        'L' => \&_resolv_link,
        'X' => sub { '' },
        'Z' => sub { '' },
    );
    if (exists $interiors{$seq_command}) {
        my $code = $interiors{$seq_command};
        return $code->($self, $seq_command, $seq_argument, $pod_seq);
    } else {
        return sprintf '%s<%s>', $seq_command, $seq_argument;
    }
}

sub _resolv_link {
    my ($self, $cmd, $arg) = @_;

    local $self->_private->{InsideLink} = 1;

    my ($text, $inferred, $name, $section, $type) =
      # perlpodspec says formatting codes can occur in all parts of an L<>
      map { $_ && $self->interpolate($_, 1) }
      Pod::ParseLink::parselink($arg);
    my $url = '';

    if ($type eq 'url') {
        $url = $name;
    }

    # if we don't know how to handle the url just print the pod back out
    if (!$url) {
        return sprintf '%s<%s>', $cmd, $arg;
    }

    $text ||= $inferred;
    return $url eq $text ?
        sprintf '[%s]', $url :
        sprintf '[%s:title=%s]', $url, $text;
}

sub format_header {
    my ($level, $paragraph) = @_[1,2];
    sprintf '%s %s', '*' x $level, $paragraph;
}

1;
__END__

=head1 SYNOPSIS

    my $parser = Pod::Hatena->new;
    $parser->parse_from_filehandle(\*STDIN);
    print $parser->as_hatena;

=head1 DESCRIPTION

This module subclasses L<Pod::Parser> and converts POD to Hatena.

Literal characters in Pod that are special in Hatena are backslash-escaped
(except those in verbatim blocks or C&lt;code&gt; sections).

This module is strongly inspired by Pod::Markdown

=head1 SAMPLE

=head2 List

=over

=item item1

=item item2

=back

=head2 Formating

Currently C<text> C<html> are available.

=head3 html

=begin html

<b>In HTML block, E<lt> and E<gt> will not be escaped.</b>

=end html

=head3 text

=begin text

Feel free to write any Hatena sentences.

|* hello |
|table|

>|perl|
use Pod::Hatena;
||<

=end text
