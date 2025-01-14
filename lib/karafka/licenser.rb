# frozen_string_literal: true

module Karafka
  # Checks the license presence for pro and loads pro components when needed (if any)
  class Licenser
    # Location in the gem where we store the public key
    PUBLIC_KEY_LOCATION = File.join(Karafka.gem_root, 'certs', 'karafka-pro.pem')

    private_constant :PUBLIC_KEY_LOCATION

    # Tries to prepare license and verifies it
    #
    # @param license_config [Karafka::Core::Configurable::Node] config related to the licensing
    def prepare_and_verify(license_config)
      prepare(license_config)
      verify(license_config)
    end

    private

    # @param license_config [Karafka::Core::Configurable::Node] config related to the licensing
    def prepare(license_config)
      # If there is token, no action needed
      # We support a case where someone would put the token in instead of using one from the
      # license. That's in case there are limitations to using external package sources, etc
      return if license_config.token

      begin
        license_config.token || require('karafka-license')
      rescue LoadError
        return
      end

      license_config.token = Karafka::License.token
    end

    # Check license and setup license details (if needed)
    # @param license_config [Karafka::Core::Configurable::Node] config related to the licensing
    def verify(license_config)
      # If no license, it will just run LGPL components without anything extra
      return unless license_config.token

      public_key = OpenSSL::PKey::RSA.new(File.read(PUBLIC_KEY_LOCATION))

      # We gsub and strip in case someone copy-pasted it as a multi line string
      formatted_token = license_config.token.strip.delete("\n").delete(' ')
      decoded_token = Base64.decode64(formatted_token)

      begin
        data = public_key.public_decrypt(decoded_token)
      rescue OpenSSL::OpenSSLError
        data = nil
      end

      details = data ? JSON.parse(data) : raise_invalid_license_token(license_config)

      license_config.entity = details.fetch('entity')
    end

    # Raises an error with info, that used token is invalid
    # @param license_config [Karafka::Core::Configurable::Node]
    def raise_invalid_license_token(license_config)
      # We set it to false so `Karafka.pro?` method behaves as expected
      license_config.token = false

      raise(
        Errors::InvalidLicenseTokenError,
        <<~MSG.tr("\n", ' ')
          License key you provided is invalid.
          Please reach us at contact@karafka.io or visit https://karafka.io to obtain a valid one.
        MSG
      )
    end
  end
end
