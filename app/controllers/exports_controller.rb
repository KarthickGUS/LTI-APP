require "httparty"
require "axlsx"
require "json"

class ExportsController < ApplicationController
  BATCH_SIZE = 500
  def export_course
    base_url = ENV["LCCA_URL"]
    token = ENV["LCCA_TOKEN"]

    headers = {
      "Authorization" => "Bearer #{token}"
    }

    courses = JSON.parse(File.read(course_ids_file))

    start_index = read_batch_progress
    end_index = [ start_index + BATCH_SIZE - 1, courses.size - 1 ].min

    puts "Processing batch: #{start_index} → #{end_index}"

    (start_index..end_index).each do |i|
      c = courses[i]
      course_id = c["course_id"]
      course_name = c["course_name"]

      puts "Processing Course ID: #{course_id}"

      # 🔹 Groups
      groups = HTTParty.get(
        "#{base_url}/api/v1/courses/#{course_id}/assignment_groups",
        headers: headers
      ).parsed_response


      group_map = groups.each_with_object({}) do |g, map|
        map[g["id"]] = {
          name: g["name"],
          weight: g["group_weight"]
        }
      end

      # 🔹 Assignments
      assignments = HTTParty.get(
        "#{base_url}/api/v1/courses/#{course_id}/assignments",
        headers: headers
      ).parsed_response

    records = []

    assignments.each do |a|
      next unless a.is_a?(Hash)

      group = group_map[a["assignment_group_id"]] || {}

      records << {
        course_id: course_id,
        course_name: course_name,
        assignment_group_id: a["assignment_group_id"],
        assignment_group_name: group[:name],
        weightage: group[:weight],
        assignment_id: a["id"],
        assignment_name: a["name"],
        submission_type: (a["submission_types"] || []).join(", "),
        created_date: format_utc(a["created_at"]),
        start_date: format_utc(a["unlock_at"]),
        due_date: format_utc(a["due_at"])
      }
    end

    append_bulk_to_json(records)

      puts "✅ Completed Course #{course_id}"
    end

    save_batch_progress(end_index + 1)

    puts "🎯 Batch Completed"

    render json: {
      message: "Batch completed",
      next_start_index: end_index + 1
    }

  rescue => e
    puts "❌ ERROR: #{e.message}"
    render json: { error: e.message }, status: 500
  end

  def export_course_ids
    base_url = ENV["CANVAS_BASE_URL"]
    token = ENV["CANVAS_API_TOKEN"]

    headers = {
      "Authorization" => "Bearer #{token}"
    }

    all_courses = []

    (1..2).each do |page|
      puts "Fetching page #{page}"

      response = HTTParty.get(
        "#{base_url}/api/v1/accounts/1/courses",
        headers: headers,
        query: {
          per_page: 100,
          page: page
        }
      )

      courses = response.parsed_response

      next unless courses.is_a?(Array)

      available_courses = courses.select do |c|
        c["workflow_state"] == "available"
      end

      formatted = available_courses.map do |c|
        {
          course_id: c["id"],
          course_name: c["name"]
        }
      end

      all_courses.concat(formatted)

      puts "Page #{page} → #{formatted.size} available courses"
    end

    File.write(course_ids_file, all_courses.to_json)

    puts "🎉 Total Available Courses: #{all_courses.size}"

    render json: {
      message: "Course IDs exported successfully",
      total_available_courses: all_courses.size
    }

  rescue => e
    puts "❌ ERROR: #{e.message}"
    render json: { error: e.message }, status: 500
  end

  def convert_json_to_excel
    json_file = Rails.root.join("tmp", "export_data.json")
    output_file = Rails.root.join("tmp", "final_export.xlsx")

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Courses") do |sheet|
      # ✅ Headers (Humanized + Submission Type LAST)
      sheet.add_row [
        "Course Id",
        "Course Name",
        "Assignment Group Id",
        "Assignment Group Name",
        "Weightage",
        "Assignment Id",
        "Assignment Name",
        "Created Date",
        "Start Date",
        "Due Date",
        "Submission Type"
      ]

      # ✅ Read JSON line by line
      File.foreach(json_file) do |line|
        row = JSON.parse(line)

        sheet.add_row [
          row["course_id"],
          row["course_name"],
          row["assignment_group_id"],
          row["assignment_group_name"],
          row["weightage"],
          row["assignment_id"],
          row["assignment_name"],
          row["created_date"],
          row["start_date"],
          row["due_date"],
          row["submission_type"]  # 👈 moved to last
        ]
      end
    end

    package.serialize(output_file)

    puts "🎉 Excel created at: #{output_file}"

    render json: { message: "Excel created successfully" }

  rescue => e
    puts "❌ ERROR: #{e.message}"
    render json: { error: e.message }, status: 500
  end

  private

    def course_ids_file
      Rails.root.join("tmp", "course_ids.json")
    end

    def format_utc(date)
      return "" unless date
      Time.parse(date).strftime("%d %b %Y, %H:%M")
    end

    def progress_file
      Rails.root.join("tmp", "export_progress.json")
    end

    def read_progress
      return 1 unless File.exist?(progress_file)

      data = JSON.parse(File.read(progress_file))
      data["last_processed_course_id"].to_i + 1
    end

    def save_progress(course_id)
      File.write(progress_file, {
          last_processed_course_id: course_id
      }.to_json)
    end

  def append_bulk_to_json(records)
    File.open(json_file, "a") do |f|
      records.each do |r|
        f.puts(r.to_json)
      end
    end
  end

  def json_file
    Rails.root.join("tmp", "export_data.json")
  end

  def batch_progress_file
    Rails.root.join("tmp", "batch_progress.json")
  end

  def read_batch_progress
    return 0 unless File.exist?(batch_progress_file)

    data = JSON.parse(File.read(batch_progress_file))
    data["last_index"].to_i
  end

  def save_batch_progress(index)
    File.write(batch_progress_file, {
      last_index: index
    }.to_json)
  end
end
