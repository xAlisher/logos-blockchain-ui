{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/ed0cde56e2eae66030886abf7efff09eaadbc805";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    # 0.2.2 is what actually runs: it is the newest tag on the module and the version
    # installed in Basecamp. The pin does not reach the shipped .lgx — the artifact bundles
    # no blockchain_module files and the IPC interface comes from our own
    # src/BlockchainBackend.rep — but a pin reading 0.2.1 while 0.2.2 serves every call is a
    # trap for whoever reads it next.
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module?ref=0.2.2";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
