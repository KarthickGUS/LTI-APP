require "httparty"
require "axlsx"
require "json"

class ExportsController < ApplicationController
  def export_course
      base_url = ENV["CANVAS_BASE_URL"]
      token = ENV["CANVAS_API_TOKEN"]

      headers = {
        "Authorization" => "Bearer #{token}"
      }

      start_id = read_progress
      puts "Starting from Course ID: #{start_id}"

      (8050..8493).each do |course_id|
        puts "Processing Course ID: #{course_id}"

        course = HTTParty.get(
          "#{base_url}/api/v1/courses/#{course_id}",
          headers: headers
        ).parsed_response

        if course.is_a?(Hash) && course["errors"]
          puts "Skipping Course #{course_id}"
          next
        end

        course_name = course["name"]

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

        assignments = HTTParty.get(
          "#{base_url}/api/v1/courses/#{course_id}/assignments",
          headers: headers
        ).parsed_response

        assignments.each do |a|
          group = group_map[a["assignment_group_id"]] || {}
          record = {
            course_id: course_id,
            course_name: course_name,
            assignment_group_id: a["assignment_group_id"],
            assignment_group_name: group[:name],
            weightage: group[:weight],
            assignment_id: a["id"],
            assignment_name: a["name"],
            created_date: format_utc(a["created_at"]),
            start_date: format_utc(a["unlock_at"]),
            due_date: format_utc(a["due_at"]),
            submission_type: (a["submission_types"] || []).join(", ")
          }

          append_to_json(record)
        end

        puts "✅ Completed Course #{course_id}"

        save_progress(course_id)
      end

    puts "🎉 JSON Export Completed"

    render json: { message: "Export completed successfully" }

  rescue => e
    puts "❌ ERROR: #{e.message}"
    render json: { error: e.message }, status: 500
  end

  private

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

  def append_to_json(record)
    File.open(json_file, "a") do |f|
      f.puts(record.to_json)
    end
  end

  def json_file
    Rails.root.join("tmp", "export_data.json")
  end
end
