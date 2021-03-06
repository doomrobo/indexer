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

def insert_torrent(fn, name, magnetlink)
  $db.execute("insert into #{$torrent_table} values ( ?, ?, ?, ? )", fn, name, magnetlink, Time.now.to_i)
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

def latest_torrents(how_many=20)
  res = $db.execute("select * from #{$torrent_table} order by date desc limit 0, ?", how_many)
  return res
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
    a = $db.execute("select url,name,magnet from #{$torrent_table} where oid = ?", url_id).flatten
    torrent = {
      :url => a[0],
      :name => a[1],
      :magnet => a[2]
    }
    urls.push(torrent)
  }
  return urls.uniq
end

def build_magnet_uri(fn)
  torrent = BEncode.load_file(fn)
  sha1 = OpenSSL::Digest::SHA1.digest(torrent['info'].bencode)
  p = {
    :xt => "urn:btih:" << Base32.encode(sha1),
    :dn => CGI.escape(torrent["info"]["name"])
  }
  Array(torrent["announce-list"]).each do |(tracker, _)|
    p[:tr] ||= []
    p[:tr] << tracker
  end
  magnet_uri  = "magnet:?xt=#{p.delete(:xt)}"
  magnet_uri << "&" << Rack::Utils.build_query(p)
  return magnet_uri
end

def get_torrent_name(fn)
  file = BEncode.load_file(fn)
  return file['info']['name']
end

get '/' do
  erb :index
end

post '/' do
  if params['file']
    @url = build_fn(params['file'][:filename])
    ext = File.extname(@url)
    if $allowed_exts.include? ext
      save_torrent(@url, params['file'][:tempfile])
      name = get_torrent_name(File.join($pubdir,@url))
      magnetlink = build_magnet_uri(File.join($pubdir, @url))
      insert_torrent(@url, name, magnetlink)
      tags = split_input(params['tags'])
      add_tags(tags)
      map_tags_to_torrents(tags, @url)
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

get '/new' do
  @urls = []
  latest_torrents.each do |torrent|
    t = {
      :name => torrent[0],
      :url => torrent[1],
      :magnet => torrent[2],
      :date => torrent[3]
    }
    @urls.push(t)
  end
  @upload_dir = $upload_dir
  erb :list
end
