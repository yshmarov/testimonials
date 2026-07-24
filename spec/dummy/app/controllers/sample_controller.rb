# frozen_string_literal: true

class SampleController < ActionController::Base
  # A host page carrying the widget, plus a "success moment" action that
  # requests a review prompt and redirects — the flow review_prompt! is for.
  def show
    render inline: <<~ERB
      <!DOCTYPE html>
      <html>
        <head><%= csrf_meta_tags %></head>
        <body>
          <h1>Sample page</h1>
          <a href="#" id="custom-opener" data-review-prompt>Open</a>
          <%= review_engine_button(class: "btn") %>
          <%= review_engine_tag %>
        </body>
      </html>
    ERB
  end

  def celebrate
    review_prompt!(params[:kind] || :testimonial)
    redirect_to "/sample"
  end
end
