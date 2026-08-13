{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/ed0cde56e2eae66030886abf7efff09eaadbc805";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module?ref=0.2.1";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
