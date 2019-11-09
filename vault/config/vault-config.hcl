backend "consul" {
    address = "consul:8500"
    path = "vault/"
}

listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = true
}

ui = true
disable_mlock = true

