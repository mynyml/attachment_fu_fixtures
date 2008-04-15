require 'fileutils'
require File.dirname(__FILE__) + '/../../../../../spec/spec_helper'

# --------------------------------------------------
# SCHEMA
# --------------------------------------------------
# (thanks to rsl for inline schema definition
#  http://github.com/rsl/stringex/tree/5aa45b8aeec2c0dd7d8f28af879d12e0b54b1bfe/test/acts_as_url_test.rb)
ActiveRecord::Base.establish_connection(
  :adapter  => 'sqlite3',
  :dbfile   => File.join(File.dirname(__FILE__), '../../db', 'mynymldb.sqlite3')
)
ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define(:version => 1) do
  create_table :images, :force => true do |t|
    t.integer :size
    t.integer :height
    t.integer :width
    t.string  :content_type
    t.string  :filename
    t.string  :thumbnail
    t.integer :parent_id
    t.integer :product_id
    t.timestamps
  end
  create_table :products, :force => true do |t|
    t.string  :brand
    t.string  :name
    t.integer :qty
    t.text    :description
    t.timestamps
  end
end
ActiveRecord::Migration.verbose = true

# --------------------------------------------------
# FIXTURES
# --------------------------------------------------
module Neverland
  IMAGE_DIR = File.join(File.dirname(__FILE__), '../assets/')
  IMAGE_FNAME = 'rails.png'

  mattr_reader :fixture_files
  @@fixture_files = {}
  @@fixture_files['images'] = %|
  peter:
    attachment_file: #{File.join(IMAGE_DIR, IMAGE_FNAME)}
    product: clock
  |
  @@fixture_files['products'] = %|
  clock:
    brand: crocodile
    name: $LABEL
    qty: 100
    description: tick, tack
  |
end

class String
  def to_fixtures
    YAML.load(ERB.new(self).result).to_hash
  end
end

Fixtures.class_eval do
  def read_fixture_files
    Neverland.fixture_files[@table_name].to_fixtures.each do |label, data|
      self[label] = Fixture.new(data, model_class)
    end
  end
end

# --------------------------------------------------
# MODELS
# --------------------------------------------------
class Image < ActiveRecord::Base
  belongs_to :product
  has_attachment :path_prefix   => File.join(File.dirname(__FILE__), '../tmp'),
                 :thumbnails    => {:sample => '100x100>'},
                 :storage       => :file_system
  validates_as_attachment
end

class Product < ActiveRecord::Base
  has_one :image
end

# --------------------------------------------------
# SPECS
# --------------------------------------------------
# TODO: spec guess_mime_type

describe "rake [spec:]db:fixtures:load handling attachment fixtures" do
  TEMP_DIR = File.join(File.dirname(__FILE__), '../tmp/')

  before(:each) do
    Fixtures.reset_cache
  end

  after(:each) do
    Image.destroy_all
  end

  after(:all) do
    FileUtils.rmdir(File.join(TEMP_DIR, '*'))
  end

  it "should add the attachment and its thumbnails to the database" do
    lambda { insert_data }.should change(Image, :count).by(2)
    Image.find(:all).select(&:parent_id).should have(1).happythought
    Image.find(:all).reject(&:parent_id).should have(1).happythought_too
  end

  it "should assign the right id to the record" do
    insert_data
    Image.find_by_filename('rails.png').id.should == data['images']['peter']['id']
  end

  it "should properly build associations that include attachments" do
    insert_data
    Product.find_by_name('clock').image.id.should == data['images']['peter']['id']
  end

  it "should link attachment models to valid attachment files" do
    insert_data
    File.exist?(Image.find_by_filename('rails.png').full_filename).should be_true
    File.exist?(Image.find_by_filename('rails.png').full_filename(:sample)).should be_true
    File.exist?(Image.find_by_filename('rails.png').full_filename(:hook!)).should_not be_true
  end

  it "should raise an exception if fixture file doesn't exist" do
    with_bad_image_path {
      lambda {
        insert_data
      }.should raise_error(Mynyml::AttachmentFuFixtures::AttachmentFileNotFound)
    }
  end

  # --------------------------------------------------
  # Helper Methods
  # --------------------------------------------------
  def insert_data(fixtures=[])
    fixtures_files = fixture_file_names if fixtures.empty?
    fixtures_files.each do |fixture_file|
      Fixtures.create_fixtures('path/to/neverland', fixture_file)
    end
  end

  def data
    @data ||= begin
      data = Neverland.fixture_files.dup
      data.each do |name, yaml|
        fixtures = yaml.to_fixtures
        fixtures.each do |label, row|
          row['id'] = Fixtures.identify(label) if row['id'].nil?
        end
        data[name] = fixtures
      end
      data
    end
  end

  def fixture_file_names
    Neverland.fixture_files.keys
  end

  def with_bad_image_path
    orig = File.join(Neverland::IMAGE_DIR, Neverland::IMAGE_FNAME)
    temp = File.join(TEMP_DIR, Neverland::IMAGE_FNAME)
    FileUtils.mv(orig, temp)
    yield
    FileUtils.mv(temp, orig)
  end
end
