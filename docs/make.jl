using Documenter
using Literate
using NumericalOcean

const EXAMPLES_DIR = joinpath(@__DIR__, "..", "examples")
const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")
const FIGURES_DIR = joinpath(@__DIR__, "src", "assets", "figures")

# Figures live in the `figures` branch of the documentation repository (where the site is also deployed),
# rather than in this one, following Oceananigans' OceananigansDocumentation
const DOCS_REPO = "github.com/jagoosw/NumericalOceanDocumentation.git"

isdir(FIGURES_DIR) || run(`git clone --depth 1 --branch figures https://$DOCS_REPO $FIGURES_DIR`)

# otherwise the deployment commits the figures as a submodule rather than the files
rm(joinpath(FIGURES_DIR, ".git"); recursive = true, force = true)

# The examples are too expensive to run here, so they are converted to markdown with plain `julia` code blocks
# (not `@example`)
examples = ["1degree_alkalinity_release.jl"]

for example in examples
    Literate.markdown(joinpath(EXAMPLES_DIR, example), GENERATED_DIR;
                      execute = false,
                      codefence = "````julia" => "````")
end

example_pages = ["Alkalinity release" => "generated/1degree_alkalinity_release.md"]

makedocs(sitename = "NumericalOcean",
         modules = [NumericalOcean],
         repo = Remotes.GitHub("jagoosw", "NumericalOcean"),
         format = Documenter.HTML(prettyurls = get(ENV, "CI", "false") == "true",
                                  edit_link = "main",
                                  canonical = "https://jagoosw.github.io/NumericalOceanDocumentation/stable/",
                                  size_threshold = nothing),
         pages = ["Home" => "index.md",
                  "Physics" => "physics.md",
                  "Biogeochemistry" => "biogeochemistry.md",
                  "Forcing data" => "forcing_data.md",
                  "Restart files" => "restarts.md",
                  "Spun-up configurations" => "configurations.md",
                  "Examples" => example_pages,
                  "API" => "api.md"],
         # most of the internals are undocumented for now
         warnonly = [:missing_docs, :cross_references])

deploydocs(repo = "github.com/jagoosw/NumericalOcean.git",
           deploy_repo = DOCS_REPO,
           devbranch = "main",
           push_preview = true)
