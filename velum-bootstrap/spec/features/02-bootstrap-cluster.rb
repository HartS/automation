require "spec_helper"
require 'yaml'

feature "Boostrap cluster" do

  let(:node_number) { environment["minions"].count { |element| element["role"] != "admin" } }
  let(:hostnames) { environment["minions"].map { |m| m["fqdn"] if m["role"] != "admin" }.compact }

  before(:each) do
    unless self.inspect.include? "User registers"
      login
    end
  end

  # Using append after in place of after, as recommended by
  # https://github.com/mattheworiordan/capybara-screenshot#common-problems
  append_after(:each) do
    Capybara.reset_sessions!
  end

  scenario "User accepts all minions" do
    visit "/setup/discovery"

    puts ">>> Wait until all #{node_number} minions are pending to be accepted"
    with_screenshot(name: :pending_minions) do
      expect(page).to have_selector("a", text: "Accept Node", count: node_number, wait: 400)
    end
    puts "<<< All minions are pending to be accepted"

    puts ">>> Wait for accept-all button to be enabled"
    with_screenshot(name: :accept_button_enabled) do
      expect(page).to have_button("accept-all", disabled: false, wait: 20)
    end
    puts "<<< accept-all button enabled"

    puts ">>> Click to accept all minion keys"
    with_screenshot(name: :accept_button_click) do
      click_button("accept-all")
    end

    # ugly workaround for https://bugzilla.suse.com/show_bug.cgi?id=1050450
    # FIXME: drop it when bug is fixed
    sleep 30
    visit "/setup/discovery"

    # Min of 240 seconds, Max of 600 seconds, ideal = nodes * 30
    accept_timeout = [[240, node_number * 30].max, 600].min
    puts ">>> Wait until Minion keys are accepted by salt (Timeout: #{accept_timeout})"
    with_screenshot(name: :accepted_keys) do
      expect(page).to have_css("input[name='roles[worker][]']", count: node_number, wait: accept_timeout)
    end
    puts "<<< Minion keys accepted in Velum"

    puts ">>> Waiting until Minions are accepted in Velum"
    with_screenshot(name: :accepted_minions) do
      expect(page).to have_text("#{node_number} nodes found", wait: 60)
    end
    puts "<<< Minions accepted in Velum"

    # They should also appear in the UI
    hostnames.each do |hostname|
      expect(page).to have_content(hostname)
    end
  end

  scenario "User selects minion roles" do
    visit "/setup/discovery"

    puts ">>> Waiting for page to settle"
    with_screenshot(name: :wait_for_settle) do
      expect(page).to have_text("You currently have no nodes to be accepted for bootstrapping", wait: 120)
    end
    puts "<<< Page has settled"

    puts ">>> Selecting minion roles"
    with_screenshot(name: :select_minion_roles) do
      environment["minions"].each do |minion|
        if ["master", "worker"].include?(minion["role"])
          within("tr", text: minion["minionId"] || minion["minionID"]) do
            find(".#{minion["role"]}-btn").click
          end
        end
      end
    end
    puts "<<< Minion roles selected"

    puts ">>> Confirm roles selection"
    with_screenshot(name: :roles_selection) do
      click_button("set-roles")
    end

    if node_number < 3
      # a modal with a warning will appear as we only have #{node_number} nodes
      with_screenshot(name: :cluster_too_small) do
        expect(page).to have_content("Cluster is too small")
        click_button "Proceed anyway"
      end
    end
  end

  scenario "User bootstraps the cluster" do
    visit "/setup/bootstrap"

    puts ">>> Configuring last settings"
    with_screenshot(name: :bootstrap_cluster_settings) do
      fill_in "settings_apiserver", with: environment["kubernetesExternalHost"]
      fill_in "settings_dashboard_external_fqdn", with: environment["dashboardExternalHost"]
    end
    puts "<<< Last settings configured"

    puts ">>> Bootstrapping cluster"
    with_screenshot(name: :bootstrap_cluster) do
      expect(page).to have_button(value: "Bootstrap cluster", disabled: false)
      click_on "Bootstrap cluster"
    end

    # Min of 1800 seconds, Max of 7200 seconds, ideal = nodes * 120 seconds
    orchestration_timeout = [[1800, node_number * 120].max, 7200].min
    puts ">>> Wait until orchestration is complete (Timeout: #{orchestration_timeout})"
    with_screenshot(name: :orchestration_complete) do
      within(".nodes-container") do
        expect(page).to have_css(".fa-check-circle-o", count: node_number, wait: orchestration_timeout)
      end
    end
    puts "<<< Orchestration completed"
  end

  scenario "User downloads the kubeconfig file" do
    visit "/"

    expect(page).to have_text("You currently have no nodes to be accepted for bootstrapping", wait: 120)

    expect(page).to have_text("kubectl config")
    with_screenshot(name: :download_kubeconfig) do
      click_on "kubectl config"
    end
    expect(page).to have_text("Log in to Your Account")
    with_screenshot(name: :oidc_login) do
      fill_in "login", with: "test@test.com"
      fill_in "password", with: "password"
      click_button "Login"
    end
    expect(page).to have_text("apiVersion")
    File.write("kubeconfig", Nokogiri::HTML(page.body).xpath("//pre").text)
  end
end
