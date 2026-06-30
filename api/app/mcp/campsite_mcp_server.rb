# frozen_string_literal: true

# A thin MCP::Server subclass that computes the resources catalog lazily.
#
# The gem takes `resources:` as a static array and iterates it at construction, so a
# dynamic, per-user resources list would otherwise run its DB queries on *every* MCP
# request (including every tools/call). Overriding `list_resources` defers that work
# to an actual `resources/list` call. The handler the server binds at construction
# (`method(:list_resources)`) resolves to this override.
class CampsiteMcpServer < MCP::Server
  def initialize(resources_provider:, **kwargs)
    @resources_provider = resources_provider
    super(**kwargs)
  end

  private

  def list_resources(request)
    self.resources = @resources_provider.call
    super
  end
end
