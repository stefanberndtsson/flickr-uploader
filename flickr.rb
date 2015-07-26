#!/usr/bin/env ruby

$: << "."

require 'yaml'
require 'common'
require 'pp'
require 'flickraw'

class Flickr
  require 'flickraw'
  require 'time'

  def initialize(apifile)
    @apidata = YAML.load(File.read(apifile))
    FlickRaw.api_key = @apidata[:key]
    FlickRaw.shared_secret = @apidata[:shared_secret]
    flickr.access_token = @apidata[:token]
    flickr.access_secret = @apidata[:secret]
    @login = flickr.test.login
    @flickr = flickr
  end

  def recent(num)
    list = @flickr.photos.search(user_id: @login.id)
    list.to_a[0..num-1].map {|x| Photo.new(@flickr, x) }
  end

  def photoset(photoset_id)
    Photoset.new(@flickr, photoset_id)
  end

  def create_photoset(title, description, cover_photo_id)
    photoset = Photoset.new(@flickr, {title: title, description: description, cover_photo_id: cover_photo_id})
    photoset.create
  end

  def photosets
    @flickr.photosets.getList(user_id: @login.id).map {|x| Photoset.new(@flickr, x) }
  end

  def photo(photo_id)
    Photo.new(@flickr, photo_id)
  end

  def upload_photo(filename, title, description, tags)
    tag_string = tags.map {|x| "\"#{x}\""}.join(" ")
    photo = Photo.new(@flickr, {title: title, description: description, tag_string: tag_string})
    photo.upload(filename)
  end

  class Photoset
    attr_reader :id

    def initialize(flickr, photoset_id_or_data)
      @flickr = flickr
      if photoset_id_or_data.is_a?(FlickRaw::Response)
        @id = photoset_id_or_data.id
        @title = photoset_id_or_data.title
        @description = photoset_id_or_data.description if photoset_id_or_data.respond_to?(:description)
      elsif photoset_id_or_data.is_a?(Hash)
        @title = photoset_id_or_data[:title]
        @description = photoset_id_or_data[:description]
        @cover_photo_id = photoset_id_or_data[:cover_photo_id]
      else
        @id = photoset_id_or_data
      end
    end

    def info
      @description = nil
      @title = nil
      @info ||= @flickr.photosets.getInfo(photoset_id: @id)
    end

    def description
      @description || info.description
    end

    def title
      @title || info.title
    end

    def description=(value)
      @flickr.photosets.editMeta(photoset_id: @id, title: title, description: value)
      @description = nil
      @info = nil
    end

    def title=(value)
      @flickr.photosets.editMeta(photoset_id: @id, title: value, description: description)
      @title = nil
      @info = nil
    end

    def scientific_name
      description[/^Scientific name: (.*)$/,1]
    end

    def photos
      # Needs loop. Currently only capable of fetching one page of 500
      @flickr.photosets.getPhotos(photoset_id: @id, extras: "date_upload").photo.map {|x| Photo.new(@flickr, x)}
    end

    def reorder_photos(photo_ids)
      photo_id_list = photo_ids.join(",")
      @flickr.photosets.reorderPhotos(photoset_id: @id, photo_ids: photo_id_list)
    end

    def reorder
      sorted = photos.sort_by.with_index do |x,i|
        [x.uploaded_at.strftime("%Y-%m-%d"),-i]
      end.reverse
      reorder_photos(sorted.map {|x| x.id })
    end

    def create
      @flickr.photosets.create(title: @title, description: @description, primary_photo_id: @cover_photo_id)
    end

    def add_photo(photo_id)
      @flickr.photosets.addPhoto(photoset_id: @id, photo_id: photo_id)
    end
  end

  class Photo
    attr_reader :id

    def initialize(flickr, photo_id_or_data)
      @flickr = flickr
      if photo_id_or_data.is_a?(FlickRaw::Response)
        @id = photo_id_or_data.id
        @title = photo_id_or_data.title
        @dateupload = photo_id_or_data.dateupload if photo_id_or_data.respond_to?(:dateupload)
      elsif photo_id_or_data.is_a?(Hash)
        @title = photo_id_or_data[:title]
        @description = photo_id_or_data[:description]
        @tags = photo_id_or_data[:tag_string]
      else
        @id = photo_id_or_data
      end
    end

    def info
      @dateupload = nil
      @info ||= @flickr.photos.getInfo(photo_id: @id)
    end

    def description
      info.description
    end

    def title
      info.title
    end

    def dateupload
      @dateupload || info.dateuploaded
    end

    def description=(value)
      @flickr.photos.setMeta(photo_id: @id, title: title, description: value)
      @info = nil
    end

    def title=(value)
      @flickr.photos.setMeta(photo_id: @id, title: value, description: description)
      @info = nil
    end

    def scientific_name
      description[/^Scientific name: (.*)$/,1]
    end

    def original_file
      description[/^Original file: (.*)$/,1]
    end

    def tags
      info.tags
    end

    def add_tags(new_tags)
      new_tag_string = new_tags.map {|x| "\"#{x}\""}.join(" ")
      @flickr.photos.addTags(photo_id: @id, tags: new_tag_string)
      @info = nil
    end

    def uploaded_at
      Time.at(dateupload.to_i)
    end

    def taken_at
      Time.parse(info.dates.taken)
    end

    def sets
      @flickr.photos.getAllContexts(photo_id: @id).set.map {|x| Photoset.new(@flickr, x)}
    end

    def upload(filename, retry_count = 10)
      if retry_count == 0
        STDERR.puts "Unable to upload photo #{filename}, tried 10 times..."
        return
      end
      begin
        @flickr.upload_photo(filename, title: @title, description: @description, tags: @tags)
      rescue EOFError
        STDERR.puts "Upload failed, retrying... (#{retry_count})"
        upload(filename, retry_count - 1)
      end
    end
  end
end

