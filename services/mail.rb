# encoding: utf-8
require 'erb'
require 'mail'

class Service::Mail < Service
  def receive_validate(errors)
    if settings[:addresses].to_s.empty?
      errors[:addresses] = "Is required"
      false
    elsif settings[:addresses].class != String
      errors[:addresses] = "Must be a comma-separated string"
      false
    else
      true
    end
  end

  def receive_alert
    raise_config_error unless receive_validate({})

    mm = mail_message
    mm.deliver unless mm.to.empty?
  end

  def mail_addresses
    @addresses ||=
      filter_addresses(settings[:addresses].to_s.split(/,/).map { |a| a.strip })
  end

  def mail_message
    @mail_message ||= begin
      mail = ::Mail.new
      mail.from    'Librato Metrics <metrics@librato.com>'
      mail.to      mail_addresses
      mail.header['X-Mailgun-Tag'] = 'alerts'
      mail.subject %{[Librato] Alert #{payload[:alert][:name]} has triggered!}

      if payload[:alert][:version] == 2
        output = Librato::Services::Output.new(payload)
        text = output.markdown
        html = new_html_email(output.html)
      else
        text = text_email
        html = html_email
      end

      mail.text_part do
        body text
      end

      mail.html_part do
        content_type 'text/html; charset=UTF-8'
        body html
      end

      mail.delivery_method :smtp, smtp_settings

      mail
    end
  end

  def filter_addresses(addresses)
    addresses.reject {|a| email_blacklist.include?(a.downcase) }
  end

  #TODO change when no longer "new"
  def new_html_email(html)
    <<-EOF
<html>
  <head>
    <title>Librato Metrics</title>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  </head>
  <body style="background-color: #2a2a2a; padding: 0px; margin: 0px;">
    <table width="100%" cellpadding="20" cellspacing="0">
      <tr>
        <td align="center" valign="top">
          <table width="600" cellpadding="0" cellspacing="0" class="container" style="border: 1px solid #000000;">
            <tr>
              <td align="center" valign="top">
                <div id="headbar" style="background-color: #000000;padding: 20px;border-bottom: 0px solid #000000;">
                  <div id="headlogo" style="color: #CCC; font-size: 3em; font-family: Arial; font-weight: bold; text-align: left; text-shadow: black 0px 2px 0px, #E5E5E5 0px -1px 0px; vertical-align: middle">
                    <img src="https://s3.amazonaws.com/librato_images/librato_logo.png" alt="Librato Metrics">
                  </div>
                </div>
              </td>
            </tr>
            <tr>
              <td valign="top" align="left" style="background-color: #FFFFFF;padding: 20px;font-family: Arial;font-size: 12px;line-height: 150%;color: #333333;">
                <div id="content">
                #{html}
                </div>
              </td>
            </tr>
            <tr>
              <td valign="top" align="center" style="background-color: #FFFFFF;padding: 20px;font-family: Arial;font-size: 10px;line-height: 150%;color: #333333;">
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
EOF
  end

  def html_email
    erb(unindent(<<-EOF), binding)

<html>
  <head>
    <title>Librato Metrics</title>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  </head>
  <body style="background-color: #2a2a2a; padding: 0px; margin: 0px;">
    <table width="100%" cellpadding="20" cellspacing="0">
      <tr>
        <td align="center" valign="top">
          <table width="600" cellpadding="0" cellspacing="0" class="container" style="border: 1px solid #000000;">
            <tr>
              <td align="center" valign="top">
                <div id="headbar" style="background-color: #000000;padding: 20px;border-bottom: 0px solid #000000;">
                  <div id="headlogo" style="color: #CCC; font-size: 3em; font-family: Arial; font-weight: bold; text-align: left; text-shadow: black 0px 2px 0px, #E5E5E5 0px -1px 0px; vertical-align: middle">
                    <img src="https://s3.amazonaws.com/librato_images/librato_logo.png" alt="Librato Metrics">
                  </div>
                </div>
              </td>
            </tr>
            <tr>
              <td valign="top" align="left" style="background-color: #FFFFFF;padding: 20px;font-family: Arial;font-size: 12px;line-height: 150%;color: #333333;">
                <div id="content">
                  <h2>Metric <%= h payload[:metric][:name] %> has triggered an alert!</h2>
                  <ul>
                    <li>Metric: <em><%= h payload[:metric][:name] %></em></li>
                    <% get_measurements(payload)[0..19].each do |measurement| %>
                      <li>
                        <% if measurement[:source] != 'unassigned' %>
                          <%= h measurement[:source] %> :
                        <% end %>
                        <em><%= h measurement[:value] %></em>
                      </li>
                    <% end %>
                    <li>Triggered at: <em><%= Time.at(payload[:trigger_time]).utc %></em></li>
                  </ul>
                  <p>
                    Click <a href="<%= payload_link(payload) %>">this link</a> to view the metric.
                  </p>
                </div>
              </td>
            </tr>
            <tr>
              <td valign="top" align="center" style="background-color: #FFFFFF;padding: 20px;font-family: Arial;font-size: 10px;line-height: 150%;color: #333333;">
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
EOF
  end

  def text_email
    erb(unindent(<<-EOF), binding)
      Metric <%= h payload[:metric][:name] %> has triggered an alert!

      <%- get_measurements(payload)[0..19].each do |measurement| %>
      <%= measurement[:source] != 'unassigned' ? "%s: " % [measurement[:source]] : "" %><%= h measurement[:value] %>
      <%- end %>

      Triggered at: <%= Time.at(payload[:trigger_time]).utc %>

      View the metric here: <%= payload_link(payload) %>

      --
      Librato Metrics
      metrics@librato.com - https://metrics.librato.com/
    EOF
  end
end
