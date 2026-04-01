# frozen_string_literal: true

require "test_helper"

class JsonApiResourceTest < Minitest::Test
  def setup
    User.delete_all
  end

  # --- AR object ---

  def test_serializes_ar_object_type
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(user)
    assert_equal "user", result[:type]
  end

  def test_serializes_ar_object_id_as_string
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(user)
    assert_equal user.id.to_s, result[:id]
  end

  def test_serializes_ar_object_attributes_without_id
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(user)
    assert_equal({ "name" => "Tad", "email" => "tad@example.com" }, result[:attributes])
    refute result[:attributes].key?("id")
  end

  # --- AR collection (Array) ---

  def test_serializes_array_of_ar_objects
    user1 = User.create!(name: "Tad", email: "tad@example.com")
    user2 = User.create!(name: "Bob", email: "bob@example.com")
    result = ActionFigure::Formatters::JsonApi::Resource.serialize([user1, user2])
    assert_equal 2, result.length
    assert_equal "user", result[0][:type]
    assert_equal user1.id.to_s, result[0][:id]
    assert_equal "user", result[1][:type]
    assert_equal user2.id.to_s, result[1][:id]
  end

  # --- AR::Relation ---

  def test_serializes_ar_relation_as_collection
    user = User.create!(name: "Tad", email: "tad@example.com")
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(User.all)
    assert_kind_of Array, result
    assert_equal 1, result.length
    assert_equal "user", result.first[:type]
    assert_equal user.id.to_s, result.first[:id]
  end

  # --- Unsaved AR object (nil ID) ---

  def test_serializes_unsaved_ar_object_with_nil_id
    user = User.new(name: "Tad", email: "tad@example.com")
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(user)
    assert_equal "user", result[:type]
    assert_nil result[:id]
  end

  # --- Hash passthrough ---

  def test_passes_hash_through_unchanged
    hash = { type: "user", id: "1", attributes: { name: "Tad" } }
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(hash)
    assert_equal hash, result
  end

  # --- Array of hashes passthrough ---

  def test_passes_array_of_hashes_through_unchanged
    hashes = [{ type: "user", id: "1", attributes: {} }, { type: "user", id: "2", attributes: {} }]
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(hashes)
    assert_equal hashes, result
  end

  # --- nil passthrough ---

  def test_passes_nil_through_unchanged
    result = ActionFigure::Formatters::JsonApi::Resource.serialize(nil)
    assert_nil result
  end
end
