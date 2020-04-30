#
# Author: Gary Greene <greeneg@tolharadys.net>
# Copyright: 2019 JAFAX, Inc. All Rights Reserved
#
##########################################################################
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package Buyo;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use utf8;

use boolean qw(:all);
use CGI::Carp qw(carp croak fatalsToBrowser);
use Config::IniFiles;
use Dancer2;
use JSON qw();
use Data::Dumper;
use MIME::Lite;

use feature qw(:5.26);
use experimental 'switch';

use FindBin;
use lib "$FindBin::Bin/../lib";

use Buyo::Constants;
use Buyo::Utils qw(err_log);

sub load_config {
    my $sub = (caller(0))[3];
    my $appdir = shift;

    my $config = Config::IniFiles->new(-file => "$appdir/conf.d/config.ini",
                                       -allowcontinue => 1) or
                    carp("== ERROR ==: $sub: Could not read configuration: $OS_ERROR\n");

    my %configuration = ();

    $configuration{'debug'}           = $config->val('General', 'debugging');
    $configuration{'webroot'}         = $config->val('Web', 'webpath');
    $configuration{'session_support'} = $config->val('Web', 'session_support', 0);
    $configuration{'article_mech'}    = $config->val('Web', 'article_mech', "JSON");
    $configuration{'etcd_user'}       = $config->val('etcd', 'user');
    $configuration{'etcd_password'}   = $config->val('etcd', 'pass');

    return %configuration;
}

sub get_json {
    my ($config, $json_file) = @_;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    err_log("== DEBUGGING ==: APPDIR: $config->{'appdir'}") if $config->{'debug'};
    err_log("== DEBUGGING ==: JSON FILE: $json_file") if $config->{'debug'};

    my $json_txt;
    {
        local $INPUT_RECORD_SEPARATOR;
        open my $fh, '<', "$config->{'appdir'}/$json_file" or
          croak "Unable to open $json_file";
        $json_txt = <$fh>;
        close $fh;
    }

    return $json_txt;
}

sub get_article_from_json {
    my ($config, $article, $type) = @_;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my $json_txt;
    if ($type eq 'news') {
        $json_txt      = get_json($config, "content/${article}.json");
    } elsif ($type eq 'bio') {
        $json_txt      = get_json($config, "content/guests/${article}.json");
    }
    my $json           = JSON->new();
    my $article_struct = $json->decode($json_txt);

    if ($type eq 'news') {
        my $author   = $article_struct->{'info'}->{'author'};
        my $category = $article_struct->{'info'}->{'category'};
        my $date     = $article_struct->{'info'}->{'date'};
        my $title    = $article_struct->{'title'};
        my $content  = $article_struct->{'content'};
        my $id       = $article_struct->{'id'};

        return $author, ucfirst($category), $date, $title, $content, $id;
    } elsif ($type eq 'bio') {
        my $name     = $article_struct->{'name'};
        my $photo_fn = $article_struct->{'photoFileName'};
        my $position = $article_struct->{'photoPosition'};
        my $content  = $article_struct->{'content'};

        return $name, $photo_fn, $position, $content;
    }
}

sub get_file_list {
    my ($config, $directory, $extension) = @_;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my @files;
    opendir(my $dh, "$config->{'appdir'}$directory");
    while (my $file = readdir $dh) {
        next if $file =~ /^\.\.?$/;
        next if $file !~ /^\d+\.json$/;
        err_log("== DEBUGGING ==: File '$file' found. Will add to array.") if $config->{'debug'};
        push(@files, "$config->{'appdir'}$directory/$file");
    }
    closedir $dh;

    return @files;
}

sub build_article_struct_list {
    my $config = shift;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my @files = sort { $b cmp $a} get_file_list($config, 'content', 'json');

    my @articles;
    foreach my $file (@files) {
        err_log("== DEBUGGING ==: Processing file '$file'") if $config->{'debug'};
        my (undef, $filename) = split(/.*\/content\//, $file);
        err_log("== DEBUGGING ==: filename '$filename'") if $config->{'debug'};
        my ($article, $ext) = split(/\./, $filename);
        my ($author, $category, $date, $title, $content, $id) = get_article_from_json($config, $article, 'news');
        push(@articles,
            {
                'author'    => $author,
                'category'  => $category,
                'date'      => $date,
                'title'     => $title,
                'content'   => $content,
                'id'        => $id
            }
        );
    }

    return \@articles;
}

sub get_department_contacts {
    my ($config, $appdir) = @_;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my $json_txt    = get_json($config, "departments.json");
    my $json        = JSON->new();
    my $people      = $json->decode($json_txt);

    return $people;
}

sub get_department_email_from_id {
    my ($config, $appdir, $value) = @_;
    
    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};
    err_log("== DEBUGGING ==: Input \$value: $value") if $config->{'debug'};

    my $person;
    my @people = @{get_department_contacts($config, $appdir)};

    foreach $person (@people) {
        err_log("== DEBUGGING ==: Id: $person->{'id'}") if $config->{'debug'};
        if ($person->{'id'} == $value) {
            err_log("== DEBUGGING ==: Id \$person->{'id'} equals '$value'. Retrieving email address") if $config->{'debug'};
            return $person->{'emailAddress'};
        } else {
            err_log("== DEBUGGING ==: Id does not match value. Continuing...") if $config->{'debug'};
        }
    }

    return undef;
}

sub send_email {
    my ($config, $post_values) = @_;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my $email_address = get_department_email_from_id($config, $config->{'appdir'}, $post_values->{'to_list'});
    my $email_subject = $post_values->{'email_subject'};
    my $email_body    = "Message sent from: $post_values->{'email_address'}\n\nMessage:\n$post_values->{'email_body'}\n";
    # construct email
    my $msg = MIME::Lite->new(
        From     => 'noreply@jafax.org',
        To       => $email_address,
        Subject  => $email_subject,
        Type     => 'TEXT',
        Encoding => 'quoted-printable',
        Data     => $email_body,
    );
    $msg->send('sendmail', '/usr/sbin/sendmail -t -oi -oem');
}

sub get_last_three_article_structs {
    my ($config, $articles) = @_;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    # first, cast $articles into an array
    my @articles = @{$articles};

    my $top_articles = undef;
    if (scalar(@articles) ge 3) {
        $top_articles = [
            $articles[0],
            $articles[1],
            $articles[2]
        ];
    } elsif (scalar(@articles) eq 2) {
        $top_articles = [ $articles[0], $articles[1] ];
    } else {
        $top_articles = [ $articles[0] ];
    }

    return $top_articles;
}

sub validate_page_launch_date {
    my ($launch_date, $curr_date) = @_;

    my $do_launch = false;
    if ($curr_date >= $launch_date) {
        $do_launch = true;
    }

    return $do_launch;
}

sub expire_page {
    my ($expiry_date, $curr_date) = @_;

    my $expire = false;
    if ($expiry_date != -1) {
        if ($curr_date > $expiry_date) {
            $expire = true;
        }
    }

    return $expire;
}

sub register_dynamic_route {
    my ($verb, $config, $bindings, $path) = @_;

    # un-reference to make easier to work with
    my %bindings = %$bindings;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my $class        = lc($bindings{$path}->{$verb}->{'class'});
    my $template     = lc($bindings{$path}->{$verb}->{'template'});
    err_log("== DEBUGGING ==: Registering '" . uc($verb) . "' action for path '$path'") if $config->{'debug'};
    err_log("== DEBUGGING ==: Using template '$template' for path '$path'") if $config->{'debug'};
    err_log("== DEBUGGING ==: Path '$path' has class '$class' attribute") if $config->{'debug'};
    given ($verb) {
        when ('get') {
            given ($class) {
                when ('news::article') {
                    my $article_author;
                    my $article_category;
                    my $article_content;
                    my $article_date;
                    my $article_title;
                    my $article_id;

                    get "$path" => sub {
                        my $do_launch = validate_page_launch_date($bindings{$path}->{$verb}->{'launchDate'}, time);
                        my $expire_page = expire_page($bindings{$path}->{$verb}->{'expireDate'}, time);

                        my $article  = route_parameters->get('article');
                        err_log("== DEBUGGING ==: Triggering '" . uc($verb) . "' action for path '$path'") if $config->{'debug'};
                        err_log("== DEBUGGING ==: Generating page for article '$article'") if $config->{'debug'};
                        # gather up article information
                        # get article title
                        my $article_mech = uc($config->{'configuration'}->{'article_mech'});
                        err_log("== DEBUGGING ==: Using Article Content Mechanism '$article_mech'") if $config->{'debug'};
                        given ($article_mech) {
                            when ('JSON') {
                                ($article_author, $article_category, $article_date,
                                    $article_title, $article_content, $article_id) = get_article_from_json($config, $article, 'news');
                                break;
                            }
                            default {
                                err_log("== WARNING ==: Unknown Article Content Mechanism, '$article_mech'");
                            }
                        }
                        return template $template, {
                            'webroot'       => $config->{'webroot'},
                            'site_name'     => $config->{'site_title'},
                            'page_title'    => $bindings->{$path}->{'get'}->{'summary'},
                            'copyright'     => $config->{'copyright'},
                            'license'       => $config->{'license'},
                            'author'        => $article_author,
                            'category'      => $article_category,
                            'date'          => $article_date,
                            'title'         => $article_title,
                            'page_content'  => $article_content,
                            'launch'        => $do_launch,
                            'expirePage'    => $expire_page
                        };
                    };
                }
                when ('form::mailer') {
                    get "$path" => sub {
                        my $selected_dept;

                        my $do_launch = validate_page_launch_date($bindings{$path}->{$verb}->{'launchDate'}, time);
                        my $expire_page = expire_page($bindings{$path}->{$verb}->{'expireDate'}, time);

                        my $department = query_parameters->get('department');
                        my $people = get_department_contacts($config, $config->{'appdir'});
                        if (defined($department)) {
                            $selected_dept = $department;
                            err_log("== DEBUGGING ==: Form passed query parameter value '$department'") if $config->{'debug'};
                        }
                        err_log("== DEBUGGING ==: Triggering '" . uc($verb) . "' action for path '$path'") if $config->{'debug'};
                        err_log("== DEBUGGING ==: Generating page for '$class'") if $config->{'debug'};
                        return template $template, {
                            'webroot'       => $config->{'webroot'},
                            'site_name'     => $config->{'site_title'},
                            'page_title'    => $bindings->{$path}->{'get'}->{'summary'},
                            'copyright'     => $config->{'copyright'},
                            'license'       => $config->{'license'},
                            'selected'      => $selected_dept,
                            'people'        => $people,
                            'launch'        => $do_launch,
                            'expirePage'    => $expire_page
                        };
                    };
                }
                when ('news::aggregator') {
                    get "$path" => sub {
                        my $do_launch = validate_page_launch_date($bindings{$path}->{$verb}->{'launchDate'}, time);
                        my $expire_page = expire_page($bindings{$path}->{$verb}->{'expireDate'}, time);

                        my $articles = build_article_struct_list($config);
                        err_log("== DEBUGGING ==: Triggerng '" . uc($verb) . "' action for path '$path'") if $config->{'debug'};
                        err_log("== DEBUGGING ==: Generating page for '$class'") if $config->{'debug'};
                        return template $template, {
                            'webroot'       => $config->{'webroot'},
                            'site_name'     => $config->{'site_title'},
                            'page_title'    => $bindings->{$path}->{'get'}->{'summary'},
                            'copyright'     => $config->{'copyright'},
                            'license'       => $config->{'license'},
                            'articles'      => $articles,
                            'launch'        => $do_launch,
                            'expirePage'    => $expire_page
                        }
                    };
                }
                when ('news::highlights') {
                    get "$path" => sub {
                        my $do_launch = validate_page_launch_date($bindings{$path}->{$verb}->{'launchDate'}, time);
                        my $expire_page = expire_page($bindings{$path}->{$verb}->{'expireDate'}, time);

                        my $articles = build_article_struct_list($config);
                        my $top_three = get_last_three_article_structs($config, $articles);
                        err_log("== DEBUGGING ==: Triggering '" . uc($verb) . "' action for path '$path'") if $config->{'debug'};
                        err_log("== DEBUGGING ==: Generating page for '$class'") if $config->{'debug'};
                        return template $template, {
                            'webroot'       => $config->{'webroot'},
                            'site_name'     => $config->{'site_title'},
                            'page_title'    => $bindings->{$path}->{'get'}->{'summary'},
                            'copyright'     => $config->{'copyright'},
                            'license'       => $config->{'license'},
                            'articles'      => $top_three,
                            'launch'        => $do_launch,
                            'expirePage'    => $expire_page
                        }
                    };
                }
                when ("guest::bio") {
                    get "$path" => sub {
                        my $bio_name;
                        my $bio_photo;
                        my $bio_photo_position,
                        my $bio_content;

                        my $do_launch = validate_page_launch_date($bindings{$path}->{$verb}->{'launchDate'}, time);
                        my $expire_page = expire_page($bindings{$path}->{$verb}->{'expireDate'}, time);

                        my $person = route_parameters->get('person');
                        err_log("== DEBUGGING ==: Triggering '" . uc($verb) . "' action for path '$path'") if $config->{'debug'};
                        err_log("== DEBUGGING ==: Generating page for article '$person'") if $config->{'debug'};
                        my $page_content_mech = uc($config->{'configuration'}->{'article_mech'});
                        err_log("== DEBUGGING ==: Using Article Content Mechanism '$page_content_mech'") if $config->{'debug'};
                        given ($page_content_mech) {
                            when ('JSON') {
                                ($bio_name, $bio_photo, $bio_photo_position,
                                    $bio_content) = get_article_from_json($config, $person, 'bio');
                                break;
                            }
                            default {
                                err_log("== WARNING ==: Unknown Article Content Mechanism, '$page_content_mech'");
                            }
                        }
                        return template $template, {
                            'webroot'       => $config->{'webroot'},
                            'site_name'     => $config->{'site_title'},
                            'page_title'    => $bindings->{$path}->{'get'}->{'summary'},
                            'copyright'     => $config->{'copyright'},
                            'license'       => $config->{'license'},
                            'name'          => $bio_name,
                            'photo_uri'     => $bio_photo,
                            'position'      => $bio_photo_position,
                            'page_content'  => $bio_content,
                            'launch'        => $do_launch,
                            'expirePage'    => $expire_page
                        };
                    };
                }
                when ("widget::carousel") {
                    get "$path" => sub {
                        err_log("== DEBUGGING ==: Triggering '" . uc($verb) . "' action for '$path'") if $config->{'debug'};
                        err_log("== DEBUGGING ==: Generating page for IFRAME") if $config->{'debug'};
                        return template $template, {}, { layout => "carousel" };
                    };
                }
            }
        }
        when ('put') {}
        when ('post') {}
    }
}

sub register_static_route {
    my ($verb, $config, $bindings, $path) = @_;

    # un-reference to make easier to work with
    my %bindings = %$bindings;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my $template = $bindings{$path}->{'get'}->{'template'};
    err_log("== DEBUGGING ==: Registering GET action for path '$path'") if $config->{'debug'};
    err_log("== DEBUGGING ==: Using template '$template' for path '$path'") if $config->{'debug'};
    given ($verb) {
        when ('get') {
            get "$path" => sub {
                my $do_launch = validate_page_launch_date($bindings{$path}->{$verb}->{'launchDate'}, time);
                my $expire_page = expire_page($bindings{$path}->{$verb}->{'expireDate'}, time);

                err_log("== DEBUGGING ==: Triggering GET action for path $path") if $config->{'debug'};
                err_log("== DEBUGGING ==: do_launch: $do_launch") if $config->{'debug'};
                err_log("== DEBUGGING ==: expire_page: $expire_page") if $config->{'debug'};
                return template $template, {
                    'webroot'     => $config->{'webroot'},
                    'site_name'   => $config->{'site_title'},
                    'page_title'  => $bindings->{$path}->{'get'}->{'summary'},
                    'copyright'   => $config->{'copyright'},
                    'license'     => $config->{'license'},
                    'launch'      => $do_launch,
                    'expire_page' => $expire_page
                };
            };
        }
        when ('put') {}
        when ('post') {}
    }
}

sub register_actor_route {
    my ($verb, $config, $bindings, $path) = @_;

    # un-reference to make easier to work with
    my %bindings = %$bindings;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my $template;
    my $class     = lc($bindings{$path}->{$verb}->{'class'});
    if (defined($bindings{$path}->{$verb}->{'template'})) {
        $template = lc($bindings{$path}->{$verb}->{'template'});
    } else {
        $template = 'NULL';
    }
    err_log("== DEBUGGING ==: Registering '" . uc($verb) . "' action for path '$path'") if $config->{'debug'};
    err_log("== DEBUGGING ==: Using template '$template' for path '$path'") if $config->{'debug'};
    err_log("== DEBUGGING ==: Path '$path' has class '$class' attribute") if $config->{'debug'};

    given ($verb) {
        when ('post') {
            given ($class) {
                when ('action::mailer') {
                    post "$path" => sub {
                        my $post_values = request->params;

                        my $do_launch = validate_page_launch_date($bindings{$path}->{$verb}->{'launchDate'}, time);
                        my $expire_page = expire_page($bindings{$path}->{$verb}->{'expireDate'}, time);

                        err_log("== DEBUGGING ==: Triggering '$verb' action for path '$path'") if $config->{'debug'};
                        send_email($config, $post_values);
                        if ($template ne 'NULL') {
                            return template $template, {
                                'webroot'    => $config->{'webroot'},
                                'site_name'  => $config->{'site_title'},
                                'page_title' => $bindings->{$path}->{'get'}->{'summary'},
                                'copyright'  => $config->{'copyright'},
                                'license'    => $config->{'license'},
                                'launch'     => $do_launch,
                                'expirePage' => $expire_page
                            };
                        }
                    };
                }
            }
        }
        when ('get') {}
        when ('put') {}
    }

    return true;
}

sub register_get_routes {
    my ($config, $bindings, @paths) = @_;

    # un-reference to make easier to work with
    my %bindings = %$bindings;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    foreach my $path (@paths) {
        my $type = $bindings{$path}->{'get'}->{'type'};
        if (defined($type)) {
            err_log("== DEBUGGING ==: Path '$path' has type: '$type'") if $config->{'debug'};
        } else {
            err_log("== DEBUGGING ==: Path '$path' has no defined type!") if $config->{'debug'};
        }
        given ($type) {
            when ('dynamic') {
                register_dynamic_route('get', $config, $bindings, $path);
            }
            when ('static') {
                register_static_route('get', $config, $bindings, $path);
            }
            when ('actor') {
                register_actor_route('get', $config, $bindings, $path);
            }
        }
    }

    return true;
}

sub register_post_routes {
    my ($config, $bindings, @paths) = @_;

    my $sub = (caller(0))[3];
    err_log("== DEBUGGING ==: Sub: $sub") if $config->{'debug'};

    my %bindings = %$bindings;

    foreach my $path (@paths) {
        my $type = $bindings{$path}->{'post'}->{'type'};
        if (defined($type)) {
            err_log("== DEBUGGING ==: Path '$path' has type: '$type'") if $config->{'debug'};
        } else {
            err_log("== DEBUGGING ==: Path '$path' has no defined type!") if $config->{'debug'};
        }
        given ($type) {
            when ('dynamic') {
                register_dynamic_route('post', $config, $bindings, $path);
            }
            when ('static')  {
                register_static_route('post', $config, $bindings, $path);
            }
            when ('actor')   {
                register_actor_route('post', $config, $bindings, $path);
            }
        }
    }

    return true;
}

sub main {
    my $VERSION = $Buyo::Constants::version;

    set traces  => 1;

    my %configuration = load_config(config->{appdir});

    my $sub = (caller(0))[3];

    my @getters;
    my @posters;

    my $json_txt = get_json(config, 'bindings.json');
    my $json = JSON->new();
    my $data = $json->decode($json_txt);
    my %app_config = (
        'appdir'        => config->{appdir},
        'article_mech'  => $configuration{'article_mech'},
        'debug'         => $configuration{'debug'},
        'configuration' => \%configuration,
        'site_title'    => $data->{'info'}->{'title'},
        'copyright'     => $data->{'info'}->{'copyright'},
        'license'       => $data->{'info'}->{'license'}
    );
    my %paths = %{$data->{'paths'}};

    err_log("== DEBUGGING ==: Sub $sub") if $app_config{'debug'};
    err_log('== DEBUGGING ==: Loading site endpoints from JSON:') if $app_config{'debug'};
    foreach my $path (keys %paths) {
        err_log("== DEBUGGING ==: FOUND KEY: $path") if $app_config{'debug'};
        if (exists $paths{$path}->{'get'}) {
            if ($paths{$path}->{'get'}->{'active'} eq 'true') {
                push @getters, $path;
            }
        }
        if (exists $paths{$path}->{'post'}) {
            if ($paths{$path}->{'post'}->{'active'} eq 'true') {
                push @posters, $path;
            }
        }
    }

    register_get_routes(\%app_config, \%paths, @getters);
    register_post_routes(\%app_config, \%paths, @posters);

    return true;
}

main();

true;
