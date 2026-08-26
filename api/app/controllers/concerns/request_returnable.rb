# frozen_string_literal: true

module RequestReturnable
  extend ActiveSupport::Concern

  def render_json(serializer, resource, opts = {})
    json = serializer.preload_and_render(
      resource,
      organization: current_organization,
      user: opts[:user],
      member: opts[:member],
      options: opts,
    )

    render(status: opts[:status], json: json)
  end

  def render_page(serializer, resources, opts = {})
    pagination_scope = opts.delete(:pagination_scope) || resources
    hydration_scope = opts.delete(:hydration_scope)

    pagination = CursorPagination.new(
      scope: pagination_scope,
      before: params[:before],
      after: params[:after],
      limit: params[:limit],
      order: opts[:order],
    ).run

    pagination.hydrate!(hydration_scope) if hydration_scope

    render_json(serializer, pagination, opts)
  end
end
