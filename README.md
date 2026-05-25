# docopt.cr

docopt for crystal-lang

## Installation


Add this to your application's `shard.yml`:

```yaml
dependencies:
  docopt:
    github: chenkovsky/docopt.cr
```


## Usage


```crystal
require "docopt"
describe "Docopt" do
  # TODO: Write tests

  it "works" do
    doc = <<-DOC
    Naval Fate.

    Usage:
      naval_fate ship new <name>...
      naval_fate ship <name> move <x> <y> [--speed=<kn>]
      naval_fate ship shoot <x> <y>
      naval_fate mine (set|remove) <x> <y> [--moored|--drifting]
      naval_fate -h | --help
      naval_fate --version

    Options:
      -h --help     Show this screen.
      --version     Show version.
      --speed=<kn>  Speed in knots [default: 10].
      --moored      Moored (anchored) mine.
      --drifting    Drifting mine.
    DOC
    std = {"ship" => true, "new" => false, "<name>" => ["A"], "move" => true, "<x>" => "a", "<y>" => "b", "--speed" => "3", "shoot" => false, "mine" => false, "set" => false, "remove" => false, "--moored" => nil, "--drifting" => nil, "-h" => nil, "--help" => false, "--version" => nil}
    ans = Docopt.docopt(doc, argv = ["ship", "A", "move", "a", "b", "--speed=3"])
    ans["<name>"].should eq(std["<name>"])
  end
  it "one or more" do
    doc = <<-DOC
    test
    Usage:
        naval [--files=files...]
    DOC
    ans = Docopt.docopt(doc, argv = ["--files=a.txt", "--files=b.txt"])
    farr = ans["--files"] as Array(String)
    "a.txt".should eq(farr[0])
    "b.txt".should eq(farr[1])
  end
end
```


## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/ralsina/docopt.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [chenkovsky](https://github.com/chenkovsky) chenkovsky.chen - creator, maintainer
- [ralsina](https://github.com/ralsina) Roberto Alsina - minor fixes, maintainer of a fork
