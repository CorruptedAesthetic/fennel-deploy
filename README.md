# Fennel

## Running the Distribution

In order to run everything, you'll just need to run

```bash
$ git submodule init
$ git submodule update
```

to pull the latest version of all included services.

Then, run

```bash
$ docker compose up
```

to run local copies of all required services.

## Accessing the App

You'll find Fennel Labs' build of the app at http://localhost:3000.

## Communicating with the API

Point any apps you need to interact with the Fennel API at http://localhost:1234/api/v1/. The API might take several minutes to run all tests and confirm full availability.

## Configuring Your Account
You'll need someone set up as an administrator of an API group in order to manage accounts and their related blockchain assets. Navigate to http://localhost:1234/api/dashboard/ to get started. You'll need to create an account, then follow the instructions on-screen to get set up with a group and a blockchain address.

![Group Creation](img/group.png)

From there, click Create a Wallet to get an address on our blockchain. This will give you a sequence of letters and numbers that you'll need to use to send yourself tokens.

![Create a Wallet](img/admin.png)

![Address Display](img/address.png)
