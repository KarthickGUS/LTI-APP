class CreateCanvasCredentials < ActiveRecord::Migration[7.0]
  def change
    create_table :canvas_credentials do |t|
      t.string :issuer, null: false
      t.string :client_id, null: false
      t.string :client_secret, null: false
      t.text   :access_token
      t.text   :refresh_token
      t.datetime :expires_at

      t.timestamps
    end

    add_index :canvas_credentials, :issuer, unique: true
  end
end
