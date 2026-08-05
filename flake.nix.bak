{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/38ddf92c1f240f4e420d300a1fbabb1609d5db01";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module?ref=0.2.0";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
