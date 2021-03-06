( ->
  device = null
  chartInfo = null
  sensorListener = null

  $(document).on "pagecreate", '#index', (event) ->

    $('#items').on "click", 'li.item .attributes.contains-attr-type-number', ->
      device = ko.dataFor($(this).parent('.item')[0])
      jQuery.mobile.changePage '#datalogger', transition: 'slide'

  $(document).on "pagecreate", '#datalogger', (event) ->

    Highcharts.setOptions options =
      global:
        useUTC: false

    $("#logger-attr-values").on "click", '.show ', (event) ->
      sensorValueName = $(this).parents(".attr-value").data('attr-value-name')
      if device?
        showGraph(device, sensorValueName, chartInfo?.range)
      return

    $("#logger-attr-values").on "change", ".logging-switch", (event, ui) ->
      sensorValueName = $(this).parents(".attr-value").data('attr-value-name')
      action = (if $(this).val() is 'yes' then "add" else "remove")
      $.get("/datalogger/#{action}/#{device.deviceId}/#{sensorValueName}")
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
      return

    $("#datalogger").on "change", "#chart-select-range", (event, ui) ->
      val = $(this).val()
      showGraph(chartInfo.device, chartInfo.attrName, val)
      return

  $(document).on "pagehide", '#datalogger', (event) ->
    if sensorListener?
      pimatic.socket.removeListener 'device-attribute', sensorListener
    return

  $(document).on "pagebeforeshow", '#datalogger', (event) ->
    unless device?
      jQuery.mobile.changePage '#index'
      return false
    $('#chart-info').hide()

    pimatic.socket.on 'device-attribute', sensorListener = (data) ->
      unless chartInfo? then return
      if data.id is chartInfo.device.deviceId and data.name is chartInfo.attrName
        point = [new Date().getTime(), data.value]
        serie = $("#chart").highcharts().series[0]
        shift = no
        firstPoint = null
        if serie.options.data.length > 0
          firstPoint = serie.options.data[0]
        if firstPoint?
          {from, to} = getDateRange(chartInfo.range)
          if firstPoint[0] < from.getTime()
            shift = yes
        serie.addPoint(point, redraw=yes, shift, animate=yes)
        updateChartInfo()
        pimatic.showToast __('new sensor value: %s %s', data.value, chartInfo.unit)
      return

    $('#chart-container').hide()
    
    $("#logger-attr-values").find('li.attr-value').remove()
    $.get( "datalogger/info/#{device.deviceId}", (data) ->
      for name, logged of data.loggingAttributes
        attribute = device.getAttribute(name)
        unless attribute?
          console.log "could not find attribute #{name}"
        li = $ $('#datalogger-attr-value-template').html()
        li.find('.attr-value-name').text(attribute.label)
        li.find('label').attr('for', "flip-attr-value-#{name}")
        select = li.find('select')
          .attr('name', "flip-attr-value-#{name}")
          .attr('id', "flip-attr-value-#{name}")             
        li.data('attr-value-name', name)
        val = (if logged then 'yes' else 'no')
        select.find("option[value=#{val}]").attr('selected', 'selected')
        select.slider() 
        li.find('.show').button()
        $("#logger-attr-values").append li

      $("#logger-attr-values").listview('refresh')
      for name, logged of data.loggingAttributes
        if logged 
          range = $('#chart-select-range').val()
          showGraph(device, name, range)
          return
    ).done(ajaxShowToast).fail(ajaxAlertFail)
    return


  getDateRange = (range = 'day') ->
    to = new Date
    from = new Date()

    switch range
      when "day" then from.setDate(to.getDate()-1)
      when "week" then from.setDate(to.getDate()-7)
      when "month" then from.setDate(to.getDate()-30)
      when "year" then from.setDate(to.getDate()-365)
    return {from, to}

  updateChartInfo = () ->
    chart = $("#chart").highcharts()
    data = chart.series[0].options.data
    lastPoint = null
    if data.length > 0 then lastPoint = data[data.length-1]
    if lastPoint?
      $('.last-update-time').text(Highcharts.dateFormat('%Y-%m-%d %H:%M:%S', lastPoint[0])) 
      $('.last-update-value').text(Highcharts.numberFormat(lastPoint[1], 2) + " " + chartInfo.unit)
      $('#chart-info').show()
    else
      $('#chart-info').hide()

  showGraph = (device, attrName, range = 'day') ->
    unless device
      console.log "device not found?"
      return
    attribute = device.getAttribute(attrName)
    unless attribute
      console.log "attribute not found?"
      return

    {from, to} = getDateRange(range)

    $('#chart-container').show(0)

    $.ajax(
      url: "datalogger/data/#{device.deviceId}/#{attrName}"
      timeout: 30000 #ms
      type: "POST"
      data: 
        fromTime: from.getTime()
        toTime: to.getTime()
    ).done( (data) ->
      chartInfo =
        device: device
        attrName: attrName
        range: range
        unit: attribute.unit
      options =
        title: 
          text: attribute.label
        tooltip:
          valueDecimals: 2
        yAxis:
          labels:
            format: "{value} #{attribute.unit}"
        rangeSelector:
          enabled: no
        credits:
          enabled: false
        tooltip:
          valueDecimals: 2
          valueSuffix: " " + attribute.unit
        series: [
          name: attribute.label
          data: data.data
        ]
        chart:
          events:
            load: ->
              updateChartInfo()
      chart = $("#chart").highcharts "StockChart", options
      setTimeout( (=>
        $("#chart").highcharts().reflow()
      ), 500)
    ).fail(ajaxAlertFail)

)()