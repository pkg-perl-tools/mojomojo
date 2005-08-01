package MojoMojo::Search::Plucene;

use strict;
use base qw/Catalyst::Base Plucene::Simple/;
use Plucene::Plugin::Analyzer::SnowballAnalyzer;

=head1 NAME

MojoMojo::Search::Plucene - Plucene searching in MojoMojo

=head1 DESCRIPTION

Search MojoMojo content using the Plucene search engine.

=head1 METHODS

=over 4

=item new 

Constructor

=cut

sub new {
    my ( $self, $c ) = @_;
    $self = $self->NEXT::new($c);
    $self->prepare_search_index($c);
}

# TODO:
# I can't find a way to index the path data such that we can search only a subsection of
#   the path tree.  For now, we can simply get all search results and ignore those that don't
#   have a key that matches the path we are looking for.

# Not all analyzers are created equal...the SnowballAnalyzer appears to work the best
sub _parsed_query {
    my ($self, $query, $default) = @_;
    my $parser = Plucene::QueryParser->new({
      analyzer => Plucene::Plugin::Analyzer::SnowballAnalyzer->new(),
      default  => $default
    });
    $parser->parse($query);
}

sub _writer {
    my $self = shift;
    return Plucene::Index::Writer->new(
      $self->_dir,
      Plucene::Plugin::Analyzer::SnowballAnalyzer->new(),
      0
    );
}

=item update_index <page>

update the index for a given page.

=cut

# updates the search index when page data changes
sub update_index {
    my ($self, $page) = @_;
    return undef unless ($page && $page->content);

    my $content = $page->content;
    my $key = $page->path;

    $self->delete_document($key) if ($self->indexed($key));

    # Q: should we be indexing the abstract, comments, and tags?
    # FIXME: Should index comments and tags at least.
    my $text = $content->body;
    $text .= " " . $content->abstract if ($content->abstract);
    $text .= " " . $content->comments if ($content->comments);

    # translate the path into plain text so we can use it in the search query later
    my $fixed_path = $key;
    $fixed_path =~ s/\//X/g;

    my %data = (
        $key => {
            _author => $content->creator->login,
            _path => $fixed_path,
            date => ($content->created) ? $content->created->ymd : "",
            tags => join (" ", map { $_->tag } $page->tags ),
            text => $text,
        },
    );
    {
        # This throws some warnings...
        local $^W = 0;
        $self->add( %data );
    }
    return 1;
}

=item prepare_search_index

Create a new Plucene search index from all pages in the database.
Will do nothing if the index already exists.

=cut

sub prepare_search_index {
    my ( $self, $c ) = @_;
    my $index = $c->config->{home} . "/plucene";
    return if ( -e $index . "/segments" );

    # Plucene::Simple doesn't seem to tell Plucene to create a new index properly,
    # so we have to create a new segments file ourselves
    open SEGMENTS, ">$index/segments";
    close SEGMENTS;

    my $p = $self->open($index);

    $c->log->info( "Initializing Plucene search index..." ) if $c->debug;
    # loop through all latest-version pages
    my $count = 0;
    my $it = MojoMojo::M::Core::Page->retrieve_all;
    while ( my $page = $it->next ) {
        $p->update_index( $page );
        $count++;
    }

    $p->optimize;

    $self->log->info( "Indexed $count pages" ) if $self->debug;
}

=back

=head1 SEE ALSO

L<MojoMojo>, L<Plucene>

=head1 AUTHORS

Andy Grundman C<andy@hybridized.org>
Marcus Ramberg <mramberg@cpan.org>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

=cut

1;
