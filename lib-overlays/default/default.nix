final: prev: {
  gleam-purifier = {
    readLock = import ./read-lock.nix { lib = final; };
  };
}
