# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "echarts", to: "https://cdn.jsdelivr.net/npm/echarts@5.4.3/dist/echarts.esm.min.js"
pin_all_from "app/javascript/controllers", under: "controllers"
