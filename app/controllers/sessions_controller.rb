require "base64"
require "json"
require 'uri'

class SessionsController < Devise::SessionsController
  theme :theme_chosen
  before_action :auto_sign_in

  def auto_sign_in
    return if user_signed_in? || ENV['TF_ECS_SERVICE_NAME'].blank?

    user = nil

    cdn_key_header = request.headers['X-CDN-Key']
    cdn_key = ENV['CDN_KEY']
    unless cdn_key.blank?
      if cdn_key == cdn_key_header
        email = URI.decode(request.headers['x-user-email'] || '')
        puts "try auto sign in with '#{email}'"
        unless email.blank?
          user = User.where('email = ?', email).first
        end
      end
    end

    if user
      flash.discard
      sign_in user
      redirect_to admin_root_path
    end
  end
end
