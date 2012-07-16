require 'rubygems'
require 'sinatra'
require 'sqlite3'
require 'erb'


configure do
  set :port, 8080
  set :environment, :production
  $upload_dir = 'i'
  db_name = "torrents.db"
  $torrent_table = "torrents"
  $tag_table = "tags"
  $map_table = "tagmap"

  if ARGV[0] == "create"
    if File.exists? db_name
      File.delete db_name
    end
    pubdir = File.join('public', $upload_dir)
    if File.directory? pubdir
      Dir.foreach(pubdir) {|f|
        fn = File.join(pubdir,f)
        File.delete(fn) if !File.directory?(fn)
      }
    else
      Dir.mkdir(pubdir)
    end
    db = SQLite3::Database.new(db_name)
    db.execute("create table #{$torrent_table} (url text)")
    db.execute("create table #{$tag_table} (tag text)")
    db.execute("create table #{$map_table} (tag int, url int)")
  end

  $db = SQLite3::Database.new(db_name)  
end

def randomize(hash)
  a = 0
  hash[:len] ||= 10
  for i in 1..hash[:len]
    a *= 10
    a += rand(9)
  end
  return hash[:fn]+'_'+a.to_s
end

def build_fn(fn)
  ext = File.extname(fn)
  base = File.basename(fn, '.*')
  return randomize({:fn => base})+ext
end

def split_input(input)
  return input.split /[ *,*;*.*\/*]/
end

def tag_exists?(tag)
  list = $db.execute("select * from #{$tag_table} where tag = ?", tag)
  return list.length > 0
end

def add_tag(tag)
  unless tag_exists? tag
    $db.execute("insert into #{$tag_table} values ( ? )", tag)
  end
  id = $db.execute("select oid from #{$tag_table} where tag = ?", tag)
  return id[0]
end

def add_tags(list)
  list.each {|tag|
    add_tag tag
  }
end

def insert_torrent(fn)
  $db.execute("insert into #{$torrent_table} values ( ? )", fn)
end

def save_torrent(fn, tmp)
  File.open(File.join('public', $upload_dir, fn), 'w') do |f|
    f.write(tmp .read)
  end
end

def tag_id_by_name(tag)
  return $db.execute("select oid from #{$tag_table} where tag = ?", tag)
end

def torrent_id_by_url(url)
  res = $db.execute("select oid from #{$torrent_table} where url = ?", url)
  return res[0][0]
end

def make_tag_assoc(tag_id, torrent_id)
  $db.execute("insert into #{$map_table} values ( ?, ? )", tag_id, torrent_id)
end

def map_tags_to_torrents(taglist, url)
  torrent_id = torrent_id_by_url url
  taglist.each {|tag|
    tag_id = tag_id_by_name tag
    make_tag_assoc(tag_id, torrent_id)
  }
end

def build_arr(taglist)
  return "( #{taglist.join(', ')} )"
end

def tag_ids_from_names(tags)
  tag_ids = []
  tags.each {|tag|
    tag_ids.push(tag_id_by_name(tag))
  }
  tag_ids.flatten!
  return tag_ids
end

def urls_from_tag_ids(tag_ids)
  urls = []
  url_ids = $db.execute("select url, count(*) num from #{$map_table} where tag in #{build_arr(tag_ids)} group by url having num = #{tag_ids.length}")
  url_ids.flatten.each {|url_id|
    urls.push($db.execute("select url from #{$torrent_table} where oid = ?", url_id));
  }
  return urls.flatten.uniq
end

get '/' do
  erb :index
end

post '/' do
  if params['file']
    @fn = build_fn(params['file'][:filename])
    if ext == '.torrent'
      insert_torrent(@fn)
      tags = split_input(params['tags'])
      add_tags(tags)
      map_tags_to_torrents(tags, @fn)
      save_torrent(@fn, params['file'][:tempfile])
      erb :upload
    else
      @error = "Bad file type '#{ext}'"
      erb :error
    end
  else
    @error = "No file uploaded."
    erb :error
  end
end

get '/search' do
  if params['search']
    unless params['search'].strip.gsub(/\s+/, ' ') =~ /^\s*$/
      tags = split_input(params['search'])
      tag_ids = tag_ids_from_names(tags)
      @urls = urls_from_tag_ids(tag_ids)
      erb :list
    else
      @error = "Search query was blank."
      erb :error
    end
  else
    @error = "No search query parameter passed."
    erb :error
  end
end

__END__

@@ index
<title>Torrent Index</title>
<form method='POST' action='/' enctype='multipart/form-data'>
  File: <br><input type='file' name='file' /><br>
  Tags: <br><input type='text' name='tags' /><br>
  <input type='submit' value='Upload' />
</form>
<hr><br>
<form method='GET' action='/search'>
Search: <input type='text' name='search' />
</form>

@@ upload
<title>Uploaded!</title>
<a href='<%= File.join($upload_dir, @fn) %>'><%= @fn %></a>

@@ list
<title>Search Results</title>
<ol>
<% @urls.each {|url| %>
<li><a href='<%= "#{$upload_dir}/#{url}" %>'><%= url %></a></li>
<% } %>
</ol>

@@ error
<title>Error!</title>
<b>Error:</b> <%= @error %>
