class QuaaTomcat < Formula
  desc "Cloud Foundry UAA running inside Apache Tomcat"
  homepage "https://github.com/cloudfoundry/uaa"

  v = "v4.20.0" # CI Managed
  # remove v from version number
  verNum = v.sub "v", ""
  url "https://github.com/starkandwayne/uaa-war-releases/releases/download/v#{verNum}/cloudfoundry-identity-uaa-#{verNum}.war"
  version v
  sha256 "373036b0135fb27ffc9475c1b53bcf160a984cf17d145013862a3cc8248829e1"

  depends_on :java => "1.8+"
  depends_on "cloudfoundry/tap/bosh-cli" => "5.2.2"
  depends_on "starkandwayne/cf/uaa-cli" => "0.0.1"

  resource "tomcat" do
    version = "9.0.12"
    url "http://www-eu.apache.org/dist/tomcat/tomcat-9/v#{version}/bin/apache-tomcat-#{version}.tar.gz"
    sha256 "1fa3d15dcbe7b1addf03cab39b27908b9e5bc3a26ab0c268c0abcc88920f51dc"
  end

  resource "manifests" do
    url "https://github.com/starkandwayne/quick-uaa-local.git", using: :git
  end

  def install
    warfile  = Dir['*.war'].first
    share.install warfile

    bosh_bin = File.join(Formula["cloudfoundry/tap/bosh-cli"].opt_bin, "bosh")
    uaa_bin  = File.join(Formula["starkandwayne/cf/uaa-cli"].opt_bin, "uaa")

    resource("manifests").stage do
      puts "Installing quaa manifests..."
      (share/"manifests").install Dir["*", ".versions"]
    end

    resource("tomcat").stage do
      puts "Installing Apache Tomcat..."
      (libexec/"tomcat").install Dir["*"]
    end

    quaa = <<-SHELL
#!/bin/bash

export TOMCAT_TGZ_PATH=#{(share/warfile)}
export BOSH_BIN=#{bosh_bin}
export UAA_BIN=#{uaa_bin}
export CATALINA_BIN=#{(libexec/"tomcat/bin/catalina.sh")}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..

#{(share/"manifests/bin/quaa")} "$@"
SHELL
    bin.mkpath
    (bin/"quaa").binwrite(quaa)
  end

  plist_options :manual => "quaa up"

  def plist; <<~EOS
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
      <dict>
        <key>Disabled</key>
        <false/>
        <key>Label</key>
        <string>#{plist_name}</string>
        <key>ProgramArguments</key>
        <array>
          <string>#{opt_bin}/quaa</string>
          <string>up</string>
        </array>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>#{libexec}/logs/launchd.out.log</string>
        <key>StandardErrorPath</key>
        <string>#{libexec}/logs/launchd.err.log</string>
      </dict>
    </plist>
  EOS
  end

  test do
    ENV["CATALINA_BASE"] = testpath
    cp_r Dir["#{libexec}/*"], testpath
    rm Dir["#{libexec}/logs/*"]

    pid = fork do
      exec bin/"uaa-catalina", "start"
    end
    sleep 3
    begin
      system bin/"uaa-catalina", "stop"
    ensure
      Process.wait pid
    end
    assert_predicate testpath/"logs/catalina.out", :exist?
  end
end
